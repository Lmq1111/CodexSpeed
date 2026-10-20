import Foundation
import CSQLite

public enum ConversationCatalog {
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) throws -> [Conversation] {
        let candidates = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        guard let path = candidates.first?.path else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { if let database { sqlite3_close(database) }; throw CatalogError.open }
        defer { sqlite3_close(database) }; sqlite3_busy_timeout(database, 200)
        var statement: OpaquePointer?
        let query = "SELECT id,COALESCE(NULLIF(name,''),title),cwd,rollout_path,COALESCE(model,'') FROM threads WHERE archived=0 ORDER BY updated_at DESC LIMIT 500"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { throw CatalogError.schema }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
        var rows: [Conversation] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(Conversation(id: string(0), title: string(1), cwd: string(2), rollout: string(3), model: string(4))) }
        return rows
    }
    public enum CatalogError: Error { case open, schema }
}
