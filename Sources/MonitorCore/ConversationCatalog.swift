import Foundation
import CSQLite

public enum ConversationCatalog {
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) throws -> [Conversation] {
        let candidates = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        guard let path = candidates.first?.path else { return [] }
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard opened == SQLITE_OK else {
            let failure = CatalogError(operation: "打开数据库", code: opened, detail: database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database")
            if let database { sqlite3_close(database) }
            throw failure
        }
        defer { sqlite3_close(database) }; sqlite3_busy_timeout(database, 200)
        var statement: OpaquePointer?
        let query = "SELECT id,COALESCE(NULLIF(name,''),title),cwd,rollout_path,COALESCE(model,'') FROM threads WHERE archived=0 ORDER BY updated_at DESC LIMIT 500"
        let prepared = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepared == SQLITE_OK else {
            throw CatalogError(operation: "查询对话目录", code: prepared, detail: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
        var rows: [Conversation] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw CatalogError(operation: "读取对话记录", code: result, detail: String(cString: sqlite3_errmsg(database)))
            }
            rows.append(Conversation(id: string(0), title: string(1), cwd: string(2), rollout: string(3), model: string(4)))
        }
    }
    public struct CatalogError: LocalizedError {
        public let operation: String
        public let code: Int32
        public let detail: String
        public var errorDescription: String? {
            let reason: String
            switch code & 0xff {
            case SQLITE_BUSY, SQLITE_LOCKED: reason = "数据库正忙，稍后自动重试"
            case SQLITE_CANTOPEN: reason = "无法打开本地数据库，请确认 Codex 数据目录可访问"
            case SQLITE_CORRUPT, SQLITE_NOTADB: reason = "数据库格式异常或无法识别"
            case SQLITE_PERM, SQLITE_AUTH: reason = "没有读取数据库的权限"
            default: reason = "\(operation)失败，稍后自动重试"
            }
            return "\(reason)（SQLite \(code)）"
        }
        public var failureReason: String? { detail }
    }
}
