import XCTest
import CSQLite
@testable import MonitorCore

final class RuntimeItemTimingTests: XCTestCase {
    func testReadOnlyIncrementalLookupIgnoresOtherThreadsAndCompletionEvents() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer { try? FileManager.default.removeItem(at:url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ command:String) { XCTAssertEqual(sqlite3_exec(db,command,nil,nil,nil),SQLITE_OK) }
        sql("CREATE TABLE logs (id INTEGER PRIMARY KEY, ts INTEGER, ts_nanos INTEGER, thread_id TEXT, target TEXT, feedback_log_body TEXT)")
        sql("INSERT INTO logs VALUES(1,100,500000000,'ours','codex_core::stream_events_utils','span: Output item item_type=\"custom_tool_call\" item_id=\"a\"')")
        sql("INSERT INTO logs VALUES(2,101,0,'ours','codex_core::stream_events_utils','from=\"output_item_done\": Output item item_type=\"custom_tool_call\" item_id=\"b\"')")
        sql("INSERT INTO logs VALUES(3,102,0,'other','codex_core::stream_events_utils','Output item item_type=\"function_call\" item_id=\"c\"')")
        let reader=RuntimeItemTimingReader(threadID:"ours",paths:[url.path])
        reader.refresh(force:true)
        XCTAssertEqual(reader.start(for:"a"),100.5);XCTAssertNil(reader.start(for:"b"));XCTAssertNil(reader.start(for:"c"))
        sql("INSERT INTO logs VALUES(4,110,0,'ours','codex_core::stream_events_utils','Output item item_type=\"function_call\" item_id=\"d\"')")
        reader.refresh(force:true)
        XCTAssertEqual(reader.start(for:"d"),110);XCTAssertEqual(reader.start(for:"a"),100.5)
        XCTAssertEqual(sqlite3_total_changes(db),4)
    }

    func testOriginalTimingCacheIsRebuiltInsteadOfMixingDefinitions() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let log=folder.appendingPathComponent("rollout.jsonl"), cache=folder.appendingPathComponent("cache.json")
        try (Data(#"{"type":"turn_context","payload":{"turn_id":"a","model":"m"}}"#.utf8) + Data([10])).write(to:log)
        let reader=UsageLogReader(path:log.path,cacheURL:cache);reader.poll();reader.saveCache()
        var object=try JSONSerialization.jsonObject(with:Data(contentsOf:cache)) as! [String:Any]
        object["version"]=2
        try JSONSerialization.data(withJSONObject:object).write(to:cache)
        let rebuilt=UsageLogReader(path:log.path,cacheURL:cache)
        XCTAssertNil(rebuilt.summary.performance.activeTurn)
        rebuilt.poll();XCTAssertEqual(rebuilt.summary.performance.activeTurn,"a")
        let updated=try JSONSerialization.jsonObject(with:Data(contentsOf:cache)) as! [String:Any]
        XCTAssertEqual(updated["version"] as? Int,5)
    }
}
