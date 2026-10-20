import XCTest
@testable import MonitorCore

private struct CharacterCounter: TokenCounting { func count(_ text: String) -> Int { text.count } }
final class ProtocolTests: XCTestCase {
    func testFragmentedAndCombinedFrames() throws {
        let a = try FrameDecoder.encode(["message": "中文"]), b = try FrameDecoder.encode(["revision": 2])
        var decoder = FrameDecoder()
        XCTAssertTrue(try decoder.append(Data(a.prefix(3))).isEmpty)
        let values = try decoder.append(Data(a.dropFirst(3)) + b)
        XCTAssertEqual(values.count, 2); XCTAssertEqual(values[0]["message"] as? String, "中文")
        XCTAssertEqual(values[1]["revision"] as? Int, 2)
        XCTAssertEqual(try decoder.append(a).count, 1)
    }
    func testRejectsOversizedFrame() { var decoder = FrameDecoder(); XCTAssertThrowsError(try decoder.append(Data([255,255,255,255]))) }
    func testPatchTransactionsDuplicatesAndRevisionGap() throws {
        var reducer = StreamReducer()
        XCTAssertTrue(try reducer.apply(["type":"snapshot", "revision":1, "conversationState":["items":["old"]]]))
        let patch: [String: Any] = ["type":"patches", "baseRevision":1, "revision":2, "patches":[["op":"add", "path":["items",1], "value":"new"]]]
        XCTAssertTrue(try reducer.apply(patch)); XCTAssertFalse(try reducer.apply(patch))
        XCTAssertEqual(reducer.state["items"] as? [String], ["old","new"])
        XCTAssertThrowsError(try reducer.apply(["type":"patches", "baseRevision":3, "revision":4, "patches":[]]))
        XCTAssertEqual(reducer.revision, 2)
        XCTAssertThrowsError(try reducer.apply(["type":"patches", "baseRevision":2, "revision":3, "patches":[["op":"replace","path":["missing"],"value":1]]]))
        XCTAssertEqual(reducer.revision, 2)
    }
    func testArrayReplaceRemoveAndObjectAdd() throws {
        var r = StreamReducer(); _ = try r.apply(["type":"snapshot","revision":1,"conversationState":["a":[1,2,3]]])
        _ = try r.apply(["type":"patches","baseRevision":1,"revision":2,"patches":[["op":"replace","path":["a",1],"value":7],["op":"remove","path":["a",0]],["op":"add","path":["ok"],"value":true]]])
        XCTAssertEqual(r.state["a"] as? [Int], [7,3]); XCTAssertEqual(r.state["ok"] as? Bool,true)
    }
}
final class MetricsTests: XCTestCase {
    func state(_ text: String, completed: Bool = false, turn: String = "turn1", started: Double = 1000, status: String = "inProgress", tool: Bool = false) -> [String: Any] {
        var items: [[String: Any]] = [["id":"m1","type":"agentMessage","text":text]]
        if tool { items.append(["id":"tool","type":"commandExecution","status":"inProgress","aggregatedOutput":"do not count me"]) }
        return ["turnHistory":["history":["entitiesByKey":["tail":["turnId":turn,"turnStartedAtMs":started * 1000,"status":status,"items":items,"completedItemIds":["m1":completed],"aeonAssistantMessageStartedAtMsById":["m1":started * 1000]]]]]]
    }
    func testSnapshotIgnoredButIncrementalTextCounted() {
        let e = MetricsEngine(counter: CharacterCounter())
        e.update(state: state("hello"), snapshot:true, revision:1, now:0, date:Date(timeIntervalSince1970:1001))
        XCTAssertNil(e.metrics.speed); XCTAssertEqual(e.metrics.sampledTokens,0)
        e.update(state: state("hello world"), snapshot:false, revision:2, now:1, date:Date(timeIntervalSince1970:1002))
        XCTAssertEqual(e.metrics.speed!,2,accuracy:0.001); XCTAssertEqual(e.metrics.sampledTokens,6)
        XCTAssertNil(e.metrics.firstLatency, "Joining an already visible answer cannot establish first-text latency")
        e.update(state: state("hello world"), snapshot:false, revision:3, now:2, date:Date(timeIntervalSince1970:1003))
        XCTAssertEqual(e.metrics.sampledTokens,6)
        e.tick(now:5,date:Date(timeIntervalSince1970:1006)); XCTAssertNil(e.metrics.speed)
    }
    func testThreeSecondWindowExcludesItsLeftBoundary() {
        let e = MetricsEngine(counter: CharacterCounter())
        e.update(state:state(""),snapshot:true,revision:1,now:0,date:Date(timeIntervalSince1970:1000))
        for i in 1...5 {
            e.update(state:state(String(repeating:"a",count:i*30)),snapshot:false,revision:i+1,now:Double(i),date:Date(timeIntervalSince1970:1000+Double(i)))
        }
        XCTAssertEqual(e.metrics.speed!,30,accuracy:0.001)
    }
    func testNewTurnLatencyAndTools() {
        let e = MetricsEngine(counter: CharacterCounter())
        e.update(state: state("old", completed:true, status:"completed"), snapshot:true, revision:1, now:0,date:Date(timeIntervalSince1970:1001))
        e.update(state: state("", turn:"turn2", started:1010), snapshot:false,revision:2,now:10,date:Date(timeIntervalSince1970:1010))
        e.update(state: state("你好👋",turn:"turn2",started:1010),snapshot:false,revision:3,now:12,date:Date(timeIntervalSince1970:1012))
        XCTAssertEqual(e.metrics.firstLatency,2); XCTAssertEqual(e.metrics.sampledTokens,3); XCTAssertEqual(e.metrics.phase,.writing)
        e.update(state: state("你好👋",completed:true,turn:"turn2",started:1010,tool:true),snapshot:false,revision:4,now:13,date:Date(timeIntervalSince1970:1013))
        XCTAssertEqual(e.metrics.phase,.tool); XCTAssertNil(e.metrics.speed); XCTAssertEqual(e.metrics.sampledTokens,3)
    }
    func testReconnectAndRevisionDoNotCreateBurst() {
        let e = MetricsEngine(counter: CharacterCounter())
        e.update(state:state("hello"),snapshot:true,revision:1,now:1,date:Date(timeIntervalSince1970:1001))
        e.update(state:state("hello there"),snapshot:false,revision:2,now:2,date:Date(timeIntervalSince1970:1002))
        e.disconnect(); XCTAssertNil(e.metrics.speed)
        e.update(state:state("hello there long unseen output"),snapshot:true,revision:10,now:20,date:Date(timeIntervalSince1970:1020))
        XCTAssertNil(e.metrics.speed)
        let oldCount = e.metrics.sampledTokens
        e.update(state:state("rewritten"),snapshot:false,revision:11,now:21,date:Date(timeIntervalSince1970:1021))
        XCTAssertEqual(e.metrics.sampledTokens,oldCount); XCTAssertNil(e.metrics.speed)
    }
    func testCompletedAndApprovalPhases() {
        let e = MetricsEngine(counter: CharacterCounter())
        for (status,expected) in [("completed",TaskPhase.done),("interrupted",.interrupted),("failed",.failed)] {
            e.update(state:state("",status:status),snapshot:true,revision:1); XCTAssertEqual(e.metrics.phase,expected)
        }
        var waiting = state(""); waiting["requests"] = [["id":"approval"]]
        e.update(state:waiting,snapshot:true,revision:2); XCTAssertEqual(e.metrics.phase,.approval)
    }
}
final class UsageTests: XCTestCase {
    func usage(_ n: Int) -> [String: Any] { ["total_tokens":n,"input_tokens":n-10,"output_tokens":10,"cached_input_tokens":20,"reasoning_output_tokens":5] }
    func record(_ id: String,_ n: Int,_ total: Int) -> [String: Any] { ["type":"token_usage_record","payload":["turn_id":id,"turn_token_usage":usage(n),"thread_token_usage":usage(total)]] }
    func start(_ id:String) -> [String: Any] { ["type":"event_msg","payload":["type":"task_started","turn_id":id,"started_at":1000]] }
    func testWholeTurnUsageReplacesAndDoesNotDoubleCount() {
        var log=LogSummary(); log.ingest(start("a")); log.ingest(record("a",100,100)); log.ingest(record("a",150,150)); log.ingest(record("a",150,150))
        XCTAssertEqual(log.usage["a"]?.total,150); XCTAssertEqual(log.total?.total,150)
        log.ingest(start("b")); log.ingest(record("b",50,200))
        XCTAssertEqual(log.previous(before:"b")?.total,150); XCTAssertEqual(log.usage["b"]?.total,50); XCTAssertEqual(log.total?.total,200)
    }
    func testPartialLinesAndTruncation() throws {
        let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:path) }
        let first=try JSONSerialization.data(withJSONObject:start("a"))
        try first.prefix(10).write(to:path)
        let reader=UsageLogReader(path:path.path); reader.poll(); XCTAssertNil(reader.summary.currentTurn)
        let handle=try FileHandle(forWritingTo:path); try handle.seekToEnd(); try handle.write(contentsOf:first.dropFirst(10)+Data([10])); try handle.close()
        reader.poll(); XCTAssertEqual(reader.summary.currentTurn,"a"); XCTAssertFalse(reader.poll())
        try Data().write(to:path); reader.poll(); XCTAssertNil(reader.summary.currentTurn)
    }
    func testLargeHistoryYieldsAndEventuallyPreservesOfficialUsage() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let noise = try JSONSerialization.data(withJSONObject: ["type":"response_item", "payload":["type":"function_call_output", "output":String(repeating:"x", count:4096)]]) + Data([10])
        var data = Data()
        for _ in 0..<512 { data.append(noise) }
        data.append(try JSONSerialization.data(withJSONObject:start("a"))); data.append(10)
        data.append(try JSONSerialization.data(withJSONObject:record("a",150,150))); data.append(10)
        try data.write(to:path)
        let reader = UsageLogReader(path:path.path)
        reader.poll(maxBytes:65536)
        XCTAssertFalse(reader.isCaughtUp)
        XCTAssertNil(reader.summary.total, "A poll must yield instead of consuming all history")
        for _ in 0..<40 { reader.poll(maxBytes:65536) }
        XCTAssertTrue(reader.isCaughtUp)
        XCTAssertEqual(reader.summary.total?.total,150)
        XCTAssertEqual(reader.summary.currentTurn,"a")
        XCTAssertFalse(reader.poll())
    }
    func testLegacyCountersDoNotOverwriteAuthoritativeCumulativeUsage() {
        var log = LogSummary(); log.ingest(start("a")); log.ingest(record("a",100,1000))
        log.ingest(["type":"event_msg","payload":["type":"token_count","info":["total_token_usage":usage(500)]]])
        XCTAssertEqual(log.total?.total,1000)
    }
    func testUnknownAndZeroNotConfused() {
        XCTAssertNil(Usage(nil)); let zero=Usage(["total_tokens":0]); XCTAssertEqual(zero?.total,0); XCTAssertNil(zero?.hit)
    }
}
final class SelectionTests: XCTestCase {
    func testNoGuessingForDuplicateTitle() {
        let rows=[Conversation(id:"a",title:"重复",cwd:"/one"),Conversation(id:"b",title:"重复",cwd:"/two")]
        XCTAssertNil(SelectionResolver.resolve(explicitID:nil,title:"重复",project:nil,conversations:rows))
        XCTAssertEqual(SelectionResolver.resolve(explicitID:nil,title:"重复",project:"two",conversations:rows)?.id,"b")
        XCTAssertEqual(SelectionResolver.resolve(explicitID:"a",title:nil,project:nil,conversations:rows)?.id,"a")
        XCTAssertNil(SelectionResolver.resolve(explicitID:nil,title:"重…",project:nil,conversations:rows))
    }
}
final class TokenizerTests: XCTestCase {
    func testOfflineTokenizerBasicGoldenAndChunkBoundaries() throws {
        let counter=try LocalTokenizer()
        XCTAssertEqual(try counter.count("Hello, world!"),4)
        XCTAssertEqual(try counter.count(""),0)
        XCTAssertEqual(try counter.count("你好，世界！"),4)
        XCTAssertEqual(try counter.count("func add(_ a: Int, _ b: Int) -> Int { a + b }"),19)
        XCTAssertEqual(try counter.count("👩🏽‍💻🚀"),9)
        XCTAssertEqual(try counter.count("中文 English 混合 123\n下一行"),10)
        XCTAssertEqual(try counter.count(String(repeating: "a", count: 100)),13)
        XCTAssertLessThan(try counter.count("hello"),try counter.count("hel")+counter.count("lo"))
    }
}
