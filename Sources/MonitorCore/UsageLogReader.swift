import Foundation

public struct LogSummary: Codable, Sendable {
    public var performance = PerformanceHistory()
    public var currentTurn: String?
    public var order: [String] = []
    public var usage: [String: Usage] = [:]
    public var starts: [String: Date] = [:]
    public var phase: TaskPhase = .unknown
    public var total: Usage?
    private var authoritativeTotal = false
    public var context: Double?
    public init() {}
    public func previous(before id: String?) -> Usage? {
        guard let id, let index = order.firstIndex(of: id), index > 0 else { return nil }
        return usage[order[index - 1]]
    }
    public mutating func ingest(_ object: [String: Any]) {
        if object["type"] as? String == "token_usage_record", let p = object["payload"] as? [String: Any],
           let response = p["response_id"] as? String, let turn = p["turn_id"] as? String,
           performance.hasResponse(response, turnID: turn) { return }
        performance.ingest(object)
        guard let type = object["type"] as? String, let p = object["payload"] as? [String: Any] else { return }
        if type == "event_msg" {
            let event = p["type"] as? String
            if event == "task_started", let id = p["turn_id"] as? String {
                if !order.contains(id) { order.append(id) }
                currentTurn = id; phase = .waiting
                if let time = p["started_at"] as? Double { starts[id] = Date(timeIntervalSince1970: time) }
                if order.count > 32 { let old = order.removeFirst(); usage.removeValue(forKey: old); starts.removeValue(forKey: old) }
            } else if event == "task_complete" || event == "turn_aborted" {
                let id = p["turn_id"] as? String
                if id == nil || id == currentTurn { phase = event == "turn_aborted" ? .interrupted : .done }
            } else if event == "token_count", let info = p["info"] as? [String: Any] {
                if !authoritativeTotal, let total = Usage(info["total_token_usage"]) { self.total = total }
                if let last = Usage(info["last_token_usage"]), let max = info["model_context_window"] as? Double, max > 0 { context = Double(last.total) / max }
            }
        } else if type == "token_usage_record" {
            if let id = p["turn_id"] as? String, let u = Usage(p["turn_token_usage"]) { usage[id] = u }
            if let total = Usage(p["thread_token_usage"]) { self.total = total; authoritativeTotal = true }
        }
    }
}
public final class UsageLogReader {
    public private(set) var summary = LogSummary()
    public private(set) var isCaughtUp = false
    private var file: FileHandle?
    private var pending = Data()
    private var searchedBytes = 0
    private static let newline = Data([10])
    private var offset: UInt64 = 0
    private static let recordMarkers = ["token_usage_record", "task_started", "task_complete", "turn_aborted", "token_count", "turn_context", "item_completed", "response_item"].map { Data(("\"" + $0 + "\"").utf8) }
    private let path: String
    private let cacheURL: URL?
    private let timings: RuntimeItemTimingReader?
    private var timingChanged = false
    private var lastSavedOffset: UInt64 = 0
    private var lastSaved = Date.distantPast
    private var fileIdentity: UInt64 = 0
    private struct Checkpoint: Codable {
        var version: Int
        var path: String
        var inode: UInt64
        var offset: UInt64
        var summary: LogSummary
    }
    public init(path: String, cacheURL: URL? = nil, timings: RuntimeItemTimingReader? = nil) {
        self.path = path; self.cacheURL = cacheURL; self.timings = timings
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        fileIdentity = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(Checkpoint.self, from: data),
           cache.version == 5, cache.path == path, cache.inode == fileIdentity, fileIdentity != 0, cache.offset <= size {
            summary = cache.summary; offset = cache.offset; lastSavedOffset = offset
            isCaughtUp = offset == size
        }
    }
    public func saveCache() {
        let completeOffset = offset - UInt64(pending.count)
        guard let cacheURL, completeOffset != lastSavedOffset || timingChanged, fileIdentity != 0 else { return }
        let cache = Checkpoint(version: 5, path: path, inode: fileIdentity, offset: completeOffset, summary: summary)
        do {
            let data = try JSONEncoder().encode(cache)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            lastSavedOffset = completeOffset; lastSaved = Date(); timingChanged = false
        } catch { /* Logs remain authoritative if a cache cannot be written. */ }
    }
    deinit { try? file?.close() }
    /// Parse incrementally, including partial lines; never reprocess an unchanged file.
    @discardableResult public func poll(maxBytes: Int = 8 * 1024 * 1024) -> Bool {
        guard !path.isEmpty else { return false }
        timings?.refresh()
        if summary.performance.resolveTiming(startForCall: { timings?.start(for: $0) }) { timingChanged = true }
        defer { if timingChanged { saveCache() } }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let identity = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        if size < offset || identity != fileIdentity {
            fileIdentity = identity; lastSavedOffset = 0; try? file?.close(); file = nil; offset = 0; pending.removeAll(); searchedBytes = 0; summary = LogSummary() }
        isCaughtUp = offset >= size
        if file == nil { file = FileHandle(forReadingAtPath: path) }
        guard let file, size > offset else { return false }
        do {
            try file.seek(toOffset: offset)
            let end = min(size, offset + UInt64(max(1, maxBytes)))
            let deadline = ProcessInfo.processInfo.systemUptime + 0.025
            while offset < end {
                guard let chunk = try file.read(upToCount: Int(min(65536, end - offset))), !chunk.isEmpty else { break }
                offset += UInt64(chunk.count); pending.append(chunk)
                while let range = pending.range(of: Self.newline, in: (pending.startIndex + searchedBytes)..<pending.endIndex) {
                    autoreleasepool {
                        let line = Data(pending[..<range.lowerBound])
                        // Filter before parsing so large tool bodies are never decoded.
                        if Self.recordMarkers.contains(where: { line.range(of: $0) != nil }),
                           let object = LogRecordDecoder.decode(line) {
                            summary.ingest(object)
                            if object["type"] as? String == "token_usage_record" {
                                if summary.performance.resolveTiming(startForCall: { timings?.start(for: $0) }) { timingChanged = true }
                            }
                        }
                    }
                    pending.removeSubrange(..<range.upperBound); searchedBytes = 0
                }
                // Do not scan the same partial record again on the next chunk.
                searchedBytes = pending.count
                if pending.count > 32 * 1024 * 1024 { pending.removeAll(); searchedBytes = 0 }
                if ProcessInfo.processInfo.systemUptime >= deadline { break }
            }
            isCaughtUp = offset >= size
            if isCaughtUp || Date().timeIntervalSince(lastSaved) >= 5 { saveCache() }
            return true
        } catch { try? file.close(); self.file = nil; return false }
    }
}
