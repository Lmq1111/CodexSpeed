import Foundation
import CSQLite

/// Read only item identities and timestamps from Codex's local tracing database.
/// Tool argument generation is a response item, distinct from tool execution.
public final class RuntimeItemTimingReader {
    private let paths: [String]
    private let threadID: String
    private var cursors: [String: Int64] = [:]
    private var starts: [String: Double] = [:]
    private var lastPoll = Date.distantPast
    private static let item = try! NSRegularExpression(pattern: #"^Output item item_type="(?:function_call|custom_tool_call)" item_id="([^"\\]+)"\s*$"#)

    public init(threadID: String, paths: [String]? = nil) {
        self.threadID = threadID
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.paths = paths ?? [home.appendingPathComponent("logs_2.sqlite").path,
                               home.appendingPathComponent("sqlite/logs_2.sqlite").path]
    }
    public func start(for id: String) -> Double? { starts[id] }

    public func refresh(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastPoll) >= 1 else { return }
        lastPoll = Date()
        for path in paths {
            var db: OpaquePointer?
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
                if let db { sqlite3_close(db) }; continue
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 20)
            // Filter the span prefix in SQLite; only the short metadata suffix is read.
            let sql = """
                SELECT id,ts,ts_nanos,
                  CASE WHEN feedback_log_body LIKE '%from="output_item_done"%' THEN ''
                  ELSE substr(feedback_log_body,instr(feedback_log_body,'Output item item_type=')) END
                FROM logs WHERE thread_id=? AND id>? AND target='codex_core::stream_events_utils'
                ORDER BY id LIMIT 1000
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            _ = threadID.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_bind_int64(statement, 2, cursors[path] ?? 0)
            while sqlite3_step(statement) == SQLITE_ROW {
                cursors[path] = sqlite3_column_int64(statement, 0)
                guard let bytes = sqlite3_column_text(statement, 3) else { continue }
                let text = String(cString: bytes)
                guard let match = Self.item.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else { continue }
                let id = String(text[range])
                let time = sqlite3_column_double(statement, 1) + sqlite3_column_double(statement, 2) / 1_000_000_000
                starts[id] = min(starts[id] ?? time, time)
            }
        }
        if starts.count > 20000 {
            starts = Dictionary(uniqueKeysWithValues: starts.sorted { $0.value > $1.value }.prefix(20000).map { ($0.key, $0.value) })
        }
    }
}
