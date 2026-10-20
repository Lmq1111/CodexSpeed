import Foundation

public final class MetricsEngine {
    public private(set) var metrics = Metrics()
    private let counter: any TokenCounting
    private var messages: [String: String] = [:]
    private var counts: [String: Int] = [:]
    private var samples: [(Double, Int)] = []
    private var turnStart: Date?
    private var baselineAt = Date.distantFuture
    private var measuredStart: Double?
    private var measuredEnd: Double?
    private var lastTextAt: Double?
    private var connected = false
    private var canMeasureLatency = true
    public init(counter: any TokenCounting) { self.counter = counter }
    public func disconnect() { connected = false; samples.removeAll(); metrics.speed = nil; metrics.points.append(SpeedPoint(time: ProcessInfo.processInfo.systemUptime, value: nil)) }
    public func applyLogs(_ log: LogSummary) {
        if metrics.turnId == nil { metrics.turnId = log.currentTurn; metrics.phase = log.phase }
        let id = metrics.turnId ?? log.currentTurn
        metrics.currentUsage = id.flatMap { log.usage[$0] }
        metrics.previousUsage = log.previous(before: id)
        if let total = log.total { metrics.totalUsage = total }
        if let context = log.context { metrics.context = context }
        if turnStart == nil, let id { turnStart = log.starts[id] }
        if !connected { metrics.phase = log.phase; metrics.turnId = log.currentTurn; metrics.currentUsage = log.currentTurn.flatMap { log.usage[$0] }; metrics.previousUsage = log.previous(before: log.currentTurn) }
    }
    public func update(state: [String: Any], snapshot: Bool, revision: Int, now: Double = ProcessInfo.processInfo.systemUptime, date: Date = Date()) {
        connected = true; metrics.eventCount += 1; metrics.revision = revision; metrics.lastEvent = date
        if snapshot { baselineAt = date; samples.removeAll(); metrics.speed = nil; messages.removeAll(); counts.removeAll() }
        if let usage = state["latestTokenUsageInfo"] as? [String: Any] {
            if let total = Usage(usage["total"]) { metrics.totalUsage = total }
            if let last = Usage(usage["last"]), let max = usage["modelContextWindow"] as? Double, max > 0 { metrics.context = Double(last.total) / max }
        }
        var turns = state["turns"] as? [[String: Any]] ?? []
        if let h = state["turnHistory"] as? [String: Any], let history = h["history"] as? [String: Any], let entities = history["entitiesByKey"] as? [String: Any] { turns += entities.values.compactMap { $0 as? [String: Any] } }
        guard let turn = turns.max(by: { ($0["turnStartedAtMs"] as? Double ?? 0) < ($1["turnStartedAtMs"] as? Double ?? 0) }), let id = turn["turnId"] as? String ?? turn["id"] as? String else { return }
        let newTurn = id != metrics.turnId
        if newTurn {
            metrics.turnId = id; metrics.firstLatency = nil; metrics.currentUsage = nil; metrics.average = nil; metrics.sampledTokens = 0
            messages.removeAll(); counts.removeAll(); samples.removeAll(); measuredStart = nil; measuredEnd = nil; lastTextAt = nil; canMeasureLatency = true
        }
        if let ms = turn["turnStartedAtMs"] as? Double { turnStart = Date(timeIntervalSince1970: ms / 1000) }
        let items = turn["items"] as? [[String: Any]] ?? []
        let completed = turn["completedItemIds"] as? [String: Any] ?? [:]
        let starts = turn["aeonAssistantMessageStartedAtMsById"] as? [String: Any] ?? [:]
        var unfinishedText = false, unfinishedTool = false
        let turnStatus = turn["status"] as? String ?? ""
        for item in items {
            let type = item["type"] as? String ?? ""
            guard let itemID = item["id"] as? String else { continue }
            let isDone = completed[itemID] as? Bool == true
            if type == "agentMessage" || type == "plan" {
                guard let text = item["text"] as? String else { continue }
                if !isDone && !text.isEmpty { unfinishedText = true }
                let old = messages[itemID] ?? ""
                if old != text {
                    if snapshot && !text.isEmpty { canMeasureLatency = false }
                    guard let count = try? counter.count(text) else { metrics.tokenizerOK = false; samples.removeAll(); continue }
                    let historical = (starts[itemID] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) < baselineAt && old.isEmpty } ?? (isDone && old.isEmpty)
                    if !snapshot && !historical && text.hasPrefix(old) {
                        // Prefix tokenization can shrink at a BPE boundary. Keep the signed adjustment.
                        let delta = count - (counts[itemID] ?? 0)
                        samples.append((now, delta)); metrics.sampledTokens += delta
                        if measuredStart == nil { measuredStart = now }
                        measuredEnd = now; lastTextAt = now
                        if canMeasureLatency, metrics.firstLatency == nil, let turnStart, !text.isEmpty { metrics.firstLatency = max(0, date.timeIntervalSince(turnStart)) }
                    } else if !snapshot && !text.hasPrefix(old) {
                        samples.removeAll(); metrics.speed = nil
                    }
                    counts[itemID] = count; messages[itemID] = text
                }
            } else if ["commandExecution", "mcpToolCall", "fileChange", "webSearch", "dynamicToolCall"].contains(type) {
                let status = item["status"] as? String
                if !isDone && (status == "inProgress" || status == "running" || status == nil) { unfinishedTool = true }
            }
        }
        let requests = state["requests"] as? [Any] ?? []
        let flags = (state["threadRuntimeStatus"] as? [String: Any])?["activeFlags"] as? [String] ?? []
        if turnStatus == "completed" { metrics.phase = .done }
        else if turnStatus == "interrupted" { metrics.phase = .interrupted }
        else if turnStatus == "failed" { metrics.phase = .failed }
        else if !requests.isEmpty || flags.contains(where: { $0.lowercased().contains("approval") || $0.lowercased().contains("input") }) { metrics.phase = .approval }
        else if unfinishedText { metrics.phase = .writing }
        else if unfinishedTool { metrics.phase = .tool }
        else { metrics.phase = messages.values.contains(where: { !$0.isEmpty }) ? .thinking : .waiting }
        if metrics.phase != .writing { samples.removeAll(); metrics.speed = nil }
        if let start = measuredStart, let end = measuredEnd, end > start { metrics.average = Double(max(0, metrics.sampledTokens)) / (end - start) }
        tick(now: now, date: date, recordPoint: false)
    }
    public func tick(now: Double = ProcessInfo.processInfo.systemUptime, date: Date = Date(), recordPoint: Bool = true) {
        samples.removeAll { $0.0 <= now - 3 }
        if connected && metrics.phase == .writing, let lastTextAt, now - lastTextAt <= 3, !samples.isEmpty {
            metrics.speed = Double(max(0, samples.reduce(0) { $0 + $1.1 })) / 3
        } else { metrics.speed = nil }
        metrics.elapsed = turnStart.map { max(0, date.timeIntervalSince($0)) }
        if recordPoint { metrics.points.append(SpeedPoint(time: now, value: metrics.speed)) }
        metrics.points.removeAll { $0.time < now - 60 }
    }
}
