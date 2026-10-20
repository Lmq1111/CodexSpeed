import Foundation

/// Numeric summaries only. No response bodies or tool arguments are retained here.
public struct RequestSample: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var turnID: String
    public var model: String
    public var effort: String
    public var outputTokens: Int
    public var generationSeconds: Double
    public var completedAt: Date
    public var speed: Double { Double(outputTokens) / generationSeconds }
}

public struct ComponentSample: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var model: String
    public var effort: String
    public var tokens: Int
    public var seconds: Double
    public var completedAt: Date
    public static func average(_ samples: [Self]) -> Double? {
        let seconds = samples.reduce(0) { $0 + $1.seconds }
        return seconds > 0 ? Double(samples.reduce(0) { $0 + $1.tokens }) / seconds : nil
    }
}

public struct TurnResult: Codable, Equatable, Sendable {
    public var id: String
    public var model = ""
    public var effort = ""
    public var startedAt: Date?
    public var completedAt: Date?
    public var duration: Double?
    public var firstToken: Double?
    public var phase: TaskPhase = .unknown
    public var usage: Usage?
    public var requestCount = 0
    public var measuredRequests = 0
    public var measuredOutput = 0
    public var generationSeconds = 0.0
    public var toolSeconds = 0.0
    public var toolCount = 0
    // Legacy interval estimate retained for audit/cache compatibility. It does not
    // establish full reasoning duration and must not be presented as model speed.
    public var average: Double? { generationSeconds > 0 ? Double(measuredOutput) / generationSeconds : nil }
}

public struct PerformanceView: Sendable {
    public var model = ""
    public var effort = ""
    public var recent: [RequestSample] = []
    public var body: [ComponentSample] = []
    public var bodyAverage: Double? { ComponentSample.average(body) }
    public var current: TurnResult?
    public var previous: TurnResult?
    public var loading = true
    // Legacy interval estimate retained for audit/cache compatibility. It does not
    // establish full reasoning duration and must not be presented as model speed.
    public var average: Double? {
        let seconds = recent.reduce(0) { $0 + $1.generationSeconds }
        return seconds > 0 ? Double(recent.reduce(0) { $0 + $1.outputTokens }) / seconds : nil
    }
    public var updatedAt: Date? { recent.last?.completedAt }
    public init() {}
}

public struct PerformanceHistory: Codable, Sendable {
    private struct Interval: Codable, Sendable {
        var start: Double
        var end: Double
        var kind = ""
    }
    private struct AwaitingTiming: Codable, Sendable {
        var sample: RequestSample
        var intervals: [Interval]
        var calls: [String: Double]
        var lowerBound: Double?
    }
    private var awaiting: [AwaitingTiming] = []
    private struct Pending: Codable, Sendable {
        var intervals: [String: Interval] = [:]
        var calls: [String: Double] = [:]
        var expected: Set<String> = []
        var invalid = false
        var hasReasoning = false
        var lastUsage: Double?
        var seenResponses: Set<String> = []
        var seenItems: Set<String> = []
    }
    public private(set) var turns: [String: TurnResult] = [:]
    public private(set) var order: [String] = []
    public private(set) var recent: [RequestSample] = []
    public private(set) var bodyRecent: [ComponentSample] = []
    public private(set) var activeTurn: String?
    private var pending: [String: Pending] = [:]
    public init() {}

    private mutating func ensure(_ id: String) {
        guard turns[id] == nil else { return }
        turns[id] = TurnResult(id: id); pending[id] = Pending(); order.append(id)
        if order.count > 32 {
            let old = order.removeFirst(); turns.removeValue(forKey: old); pending.removeValue(forKey: old)
        }
    }
    func hasResponse(_ id: String, turnID: String) -> Bool { pending[turnID]?.seenResponses.contains(id) == true }
    public mutating func ingest(_ object: [String: Any]) {
        guard let type = object["type"] as? String, let p = object["payload"] as? [String: Any] else { return }
        let event = p["type"] as? String
        let date = LogTimestamp.date(object["timestamp"])
        if type == "turn_context", let id = p["turn_id"] as? String {
            ensure(id); activeTurn = id
            turns[id]?.model = p["model"] as? String ?? ""
            turns[id]?.effort = p["effort"] as? String ?? p["reasoning_effort"] as? String ?? ""
            return
        }
        // response_item is emitted at generation completion, before tool execution.
        // It has no turn ID, so bind it to the latest explicit turn context.
        if type == "response_item", let id = activeTurn, var b = pending[id] {
            let kind = p["type"] as? String ?? ""
            if ["function_call_output", "custom_tool_call_output"].contains(kind) { return }
            if kind == "message", p["role"] as? String != "assistant" { return }
            guard let itemID = p["id"] as? String else { b.invalid = true; pending[id] = b; return }
            if ["function_call", "custom_tool_call"].contains(kind) {
                if let date { b.calls[itemID] = date.timeIntervalSince1970 } else { b.invalid = true }
            } else if ["reasoning", "message"].contains(kind) {
                b.expected.insert(itemID)
            } else { b.invalid = true }
            pending[id] = b
            return
        }
        guard let id = p["turn_id"] as? String else { return }
        if type == "event_msg" && event == "task_started" {
            ensure(id); activeTurn = id
            turns[id]?.startedAt = date ?? (p["started_at"] as? Double).map(Date.init(timeIntervalSince1970:))
            turns[id]?.phase = .waiting
        } else if type == "event_msg" && ["task_complete", "turn_aborted"].contains(event ?? "") {
            ensure(id)
            turns[id]?.completedAt = date
            turns[id]?.phase = event == "task_complete" ? .done : .interrupted
            turns[id]?.duration = Self.seconds(p["duration_ms"])
            turns[id]?.firstToken = Self.seconds(p["time_to_first_token_ms"])
        } else if type == "event_msg" && event == "item_completed" {
            guard turns[id] != nil, let item = p["item"] as? [String: Any], let itemID = item["id"] as? String,
                  let kind = item["type"] as? String, var b = pending[id], !b.seenItems.contains(itemID) else { return }
            b.seenItems.insert(itemID)
            if let start = p["started_at_ms"] as? Double, let end = p["completed_at_ms"] as? Double,
               start.isFinite, end.isFinite, start > 0, end >= start {
                if ["AgentMessage", "Reasoning"].contains(kind), end > start,
                   b.lastUsage.map({ start / 1000 >= $0 }) ?? true {
                    b.intervals[itemID] = Interval(start: start / 1000, end: end / 1000, kind: kind)
                    b.hasReasoning = b.hasReasoning || kind == "Reasoning"
                } else if ["CommandExecution", "McpToolCall", "FileChange", "WebSearch", "DynamicToolCall", "Extension"].contains(kind) {
                    turns[id]?.toolSeconds += (end - start) / 1000
                    turns[id]?.toolCount += 1
                }
            }
            pending[id] = b
        } else if type == "token_usage_record" {
            ensure(id)
            guard let response = p["response_id"] as? String, var b = pending[id], !b.seenResponses.contains(response) else { return }
            if let usage = Usage(p["turn_token_usage"]) { turns[id]?.usage = usage }
            b.seenResponses.insert(response); turns[id]?.requestCount += 1
            // The numerator is official output, including reasoning. An item-start is
            // NOT a first-token event: this is explicitly an interval estimate.
            if let fields = p["usage"] as? [String: Any],
               let output = fields["output_tokens"] as? Int, let reasoning = fields["reasoning_output_tokens"] as? Int,
               output >= 0, reasoning >= 0, reasoning <= output,
               let usage = Usage(fields), let end = date, !b.invalid,
               b.expected.isSubset(of: Set(b.intervals.keys)),
               !b.intervals.isEmpty || !b.calls.isEmpty, usage.output >= 0,
               usage.reasoning == 0 || b.hasReasoning,
               let turn = turns[id], !turn.model.isEmpty {
                let sample = RequestSample(id: response, turnID: id, model: turn.model, effort: turn.effort,
                                           outputTokens: usage.output, generationSeconds: 0, completedAt: end)
                let typed = Array(b.intervals.values)
                if Self.valid(typed, end: end, lowerBound: b.lastUsage) {
                    let bodySeconds = Self.unionSeconds(typed.filter { $0.kind == "AgentMessage" })
                    // output - reasoning includes tool arguments. It is only body
                    // output when the request contains NO generated tool calls.
                    if b.calls.isEmpty, usage.output > usage.reasoning, bodySeconds > 0 {
                        Self.append(ComponentSample(id: response, model: turn.model, effort: turn.effort,
                            tokens: usage.output - usage.reasoning, seconds: bodySeconds, completedAt: end), to: &bodyRecent)
                    }
                }
                let reasoningIntervals = typed.filter { $0.kind == "Reasoning" }
                // Some models deliver hidden reasoning in a single batch. A span
                // shorter than 50 ms cannot support this client interval estimate.
                // Skip it rather than dividing all reasoning tokens by that batch.
                let reasoningTimed = usage.reasoning == 0 || (!reasoningIntervals.isEmpty &&
                    reasoningIntervals.allSatisfy { $0.end - $0.start >= 0.05 })
                if reasoningTimed {
                    awaiting.append(AwaitingTiming(sample: sample, intervals: typed,
                                                   calls: b.calls, lowerBound: b.lastUsage))
                    if awaiting.count > 64 { awaiting.removeFirst(awaiting.count - 64) }
                }
            }
            b.intervals = [:]; b.calls = [:]; b.expected = []; b.invalid = false
            b.hasReasoning = false; b.lastUsage = date?.timeIntervalSince1970
            pending[id] = b
            resolveTiming { _ in nil }
        }
    }
    /// Missing runtime metadata may arrive after the JSONL record. Retry without
    /// ever adding incomplete output to the numerator, or counting a response twice.
    @discardableResult public mutating func resolveTiming(startForCall: (String) -> Double?) -> Bool {
        var unresolved: [AwaitingTiming] = []
        var changed = false
        for request in awaiting {
            var intervals = request.intervals
            var missing = false
            for (id, end) in request.calls {
                guard let start = startForCall(id) else { missing = true; break }
                intervals.append(Interval(start: start, end: end))
            }
            if missing { unresolved.append(request); continue }
            guard Self.valid(intervals, end: request.sample.completedAt, lowerBound: request.lowerBound) else { continue }
            let seconds = Self.unionSeconds(intervals)
            guard seconds > 0 else { continue }
            var sample = request.sample; sample.generationSeconds = seconds
            recent.append(sample); recent.sort { $0.completedAt < $1.completedAt }
            let same = recent.filter { $0.model == sample.model && $0.effort == sample.effort }
            let remove = Set(same.dropLast(10).map(\.id)); recent.removeAll { remove.contains($0.id) }
            if recent.count > 200 { recent.removeFirst(recent.count - 200) }
            turns[sample.turnID]?.measuredRequests += 1
            turns[sample.turnID]?.measuredOutput += sample.outputTokens
            turns[sample.turnID]?.generationSeconds += seconds
            changed = true
        }
        awaiting = unresolved
        return changed
    }
    private static func unionSeconds(_ intervals: [Interval]) -> Double {
        var end = -Double.infinity
        var seconds = 0.0
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            seconds += max(0, interval.end - max(end, interval.start))
            end = max(end, interval.end)
        }
        return seconds
    }
    private static func valid(_ intervals: [Interval], end: Date, lowerBound: Double?) -> Bool {
        intervals.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start &&
            $0.end <= end.timeIntervalSince1970 && (lowerBound == nil || $0.start >= lowerBound!) }
    }
    private static func append(_ sample: ComponentSample, to samples: inout [ComponentSample]) {
        samples.append(sample)
        let same = samples.filter { $0.model == sample.model && $0.effort == sample.effort }
        let remove = Set(same.dropLast(10).map(\.id))
        samples.removeAll { remove.contains($0.id) }
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
    }
    public func view(turnID: String?, fallbackModel: String = "") -> PerformanceView {
        var view = PerformanceView()
        let id = turnID ?? activeTurn
        view.current = id.flatMap { turns[$0] }
        if let id, let index = order.firstIndex(of: id), index > 0 { view.previous = turns[order[index - 1]] }
        view.model = view.current?.model.isEmpty == false ? view.current!.model : fallbackModel
        view.effort = view.current?.effort ?? ""
        view.recent = Array(recent.filter { $0.model == view.model && $0.effort == view.effort }.suffix(10))
        view.body = Array(bodyRecent.filter { $0.model == view.model && $0.effort == view.effort }.suffix(5))
        return view
    }
    private static func seconds(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber else { return nil }
        let ms = n.doubleValue
        guard ms.isFinite, ms >= 0 else { return nil }; return ms / 1000
    }
}

enum LogTimestamp {
    private static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let plain = ISO8601DateFormatter()
    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }; return fractional.date(from: s) ?? plain.date(from: s)
    }
}
