import XCTest
@testable import MonitorCore

final class PerformanceHistoryTests: XCTestCase {
    private func date(_ n: Double) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: Date(timeIntervalSince1970: n)) }
    private func context(_ id: String, _ model: String = "model-a", _ effort: String = "high") -> [String: Any] {
        ["type":"turn_context","payload":["turn_id":id,"model":model,"effort":effort]]
    }
    private func item(_ turn: String, _ id: String, _ start: Double, _ end: Double, _ kind: String = "AgentMessage") -> [String: Any] {
        ["type":"event_msg","payload":["type":"item_completed","turn_id":turn,"item":["type":kind,"id":id],"started_at_ms":start*1000,"completed_at_ms":end*1000]]
    }
    private func record(_ turn: String, _ response: String, _ end: Double, _ output: Int, _ reasoning: Int = 0) -> [String: Any] {
        let u: [String:Any] = ["input_tokens":100,"output_tokens":output,"reasoning_output_tokens":reasoning,"total_tokens":100+output]
        return ["timestamp":date(end),"type":"token_usage_record","payload":["turn_id":turn,"response_id":response,"usage":u,"turn_token_usage":u,"thread_token_usage":u]]
    }
    func testWeightedAveragePersistsAcrossIdleNewTurnAndSerialization() throws {
        var h = PerformanceHistory(); h.ingest(context("a"))
        h.ingest(item("a","m1",100,110)); h.ingest(record("a","r1",110,100))
        h.ingest(item("a","m2",200,230)); h.ingest(record("a","r2",230,900))
        XCTAssertEqual(h.view(turnID:"a").average!,25,accuracy:0.001)
        h.ingest(["type":"event_msg","timestamp":date(231),"payload":["type":"task_complete","turn_id":"a","duration_ms":131000,"time_to_first_token_ms":2500]])
        let copy = try JSONDecoder().decode(PerformanceHistory.self, from: JSONEncoder().encode(h))
        var restored = copy; restored.ingest(context("b"))
        let v = restored.view(turnID:"b")
        XCTAssertEqual(v.average!,25,accuracy:0.001)
        XCTAssertEqual(v.previous?.duration,131); XCTAssertEqual(v.previous?.firstToken,2.5)
        XCTAssertEqual(v.previous?.average,25); XCTAssertEqual(v.previous?.phase,.done)
        XCTAssertEqual(v.recent.count,2)
    }
    func testModelAndEffortNeverMixAndTenSampleLimit() {
        var h = PerformanceHistory(); h.ingest(context("a"))
        for n in 0..<12 { let t=Double(100+n*20); h.ingest(item("a","m\(n)",t,t+10));h.ingest(record("a","r\(n)",t+10,100)) }
        XCTAssertEqual(h.view(turnID:"a").recent.count,10)
        h.ingest(context("b","model-b")); XCTAssertNil(h.view(turnID:"b").average)
        h.ingest(context("c","model-a","low")); XCTAssertNil(h.view(turnID:"c").average)
        h.ingest(context("d")); XCTAssertEqual(h.view(turnID:"d").average,10)
    }
    func testUnknownOrUntimedReasoningDoesNotProduceInflatedRate() {
        var h = PerformanceHistory(); h.ingest(context("a"))
        h.ingest(item("a","m",100,101));h.ingest(record("a","r1",102,1000,900))
        XCTAssertNil(h.view(turnID:"a").average)
        h.ingest(item("a","r",110,118,"Reasoning"));h.ingest(item("a","m2",118,120));h.ingest(record("a","r2",120,1000,900))
        XCTAssertEqual(h.view(turnID:"a").average,100)
        h.ingest(record("a","r3",130,2000));XCTAssertEqual(h.view(turnID:"a").recent.count,1)
    }
    func testToolTimeDoesNotBecomeGenerationTimeAndDuplicatesDoNotRegressUsage() {
        var log = LogSummary();log.ingest(context("a"))
        log.ingest(item("a","m1",100,110));let first=record("a","r1",110,100);log.ingest(first)
        log.ingest(item("a","tool",110,180,"CommandExecution"));log.ingest(item("a","tool",110,180,"CommandExecution"))
        log.ingest(item("a","m2",180,190));log.ingest(record("a","r2",190,200));log.ingest(first)
        let v=log.performance.view(turnID:"a")
        XCTAssertEqual(v.average,15);XCTAssertEqual(v.current?.toolSeconds,70)
        XCTAssertEqual(v.current?.requestCount,2);XCTAssertEqual(v.current?.usage?.output,200)
        XCTAssertEqual(log.total?.output,200)
    }
    func testCacheRestoresResultsAndPartialLineThenRejectsReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let log=folder.appendingPathComponent("log.jsonl"), cache=folder.appendingPathComponent("cache.json")
        let records=[context("a"),item("a","m",100,110),record("a","r1",110,100)]
        var data=Data();for r in records { data.append(try JSONSerialization.data(withJSONObject:r));data.append(10) }
        let next=try JSONSerialization.data(withJSONObject:context("b"));data.append(next.prefix(10));try data.write(to:log)
        let reader=UsageLogReader(path:log.path,cacheURL:cache);reader.poll();reader.saveCache()
        let resumed=UsageLogReader(path:log.path,cacheURL:cache)
        XCTAssertEqual(resumed.summary.performance.view(turnID:"a").average,10)
        let handle=try FileHandle(forWritingTo:log);try handle.seekToEnd();try handle.write(contentsOf:next.dropFirst(10)+Data([10]));try handle.close()
        resumed.poll();XCTAssertEqual(resumed.summary.performance.activeTurn,"b")
        XCTAssertEqual(resumed.summary.performance.view(turnID:"b").average,10)
        try Data().write(to:log);resumed.poll();XCTAssertTrue(resumed.summary.performance.order.isEmpty)
    }
    func testLargeItemBodyIsNotRetainedInDecodedRecordOrCache() throws {
        let secret=String(repeating:"PRIVATE_BODY",count:100000)
        let line=Data((#"{"type":"event_msg","payload":{"type":"item_completed","turn_id":"a","item":{"type":"Reasoning","id":"r","raw_content":""# + secret + #""},"started_at_ms":100000,"completed_at_ms":110000}}"#).utf8)
        let decoded=try XCTUnwrap(LogRecordDecoder.decode(line))
        let payload=try XCTUnwrap(decoded["payload"] as? [String:Any]); let item=try XCTUnwrap(payload["item"] as? [String:Any])
        XCTAssertNil(item["raw_content"]);XCTAssertEqual(item["type"] as? String,"Reasoning")
        var h=PerformanceHistory();h.ingest(context("a"));h.ingest(decoded)
        let stored=String(decoding:try JSONEncoder().encode(h),as:UTF8.self)
        XCTAssertFalse(stored.contains("PRIVATE_BODY"))
    }
    private func call(_ id: String, _ end: Double) -> [String: Any] {
        ["type":"response_item", "timestamp":date(end), "payload":["type":"custom_tool_call", "id":id]]
    }
    func testGenerationStopsBeforeToolExecutionAndUsageReporting() {
        var h = PerformanceHistory(); h.ingest(context("a"))
        h.ingest(item("a","reason",100,110,"Reasoning"))
        h.ingest(call("args",130))
        h.ingest(item("a","tool",130,190,"McpToolCall"))
        h.ingest(record("a","r",200,1000,600))
        XCTAssertNil(h.view(turnID:"a").average) // Don't divide all output by reasoning alone.
        h.resolveTiming { $0 == "args" ? 120 : nil }
        let result = h.view(turnID:"a")
        XCTAssertEqual(result.recent.first?.generationSeconds,20) // 10 reasoning + 10 args; no 10s gap or 70s tail.
        XCTAssertEqual(result.average,50)
        XCTAssertEqual(result.current?.measuredOutput,1000) // Includes 600 reasoning exactly once.
        XCTAssertEqual(result.current?.toolSeconds,60)
        h.resolveTiming { _ in 120 }; h.ingest(record("a","r",200,1000,600))
        XCTAssertEqual(h.view(turnID:"a").recent.count,1)
    }
    func testDelayedRuntimeTimingSurvivesRestartAndIncludesToolOnlyRequest() throws {
        var h = PerformanceHistory(); h.ingest(context("a"))
        h.ingest(call("only-args",110)); h.ingest(record("a","r1",180,200))
        h = try JSONDecoder().decode(PerformanceHistory.self, from: JSONEncoder().encode(h))
        h.resolveTiming { $0 == "only-args" ? 100 : nil }
        XCTAssertEqual(h.view(turnID:"a").average,20)
        XCTAssertEqual(h.view(turnID:"a").current?.measuredOutput,200)
    }
    func testUnionExcludesGapsButDoesNotSubtractConcurrentToolFromActualGeneration() {
        var h = PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","r",100,120,"Reasoning"))
        h.ingest(item("a","m",110,130))
        h.ingest(item("a","tool",115,150,"CommandExecution"))
        h.ingest(record("a","reply",160,600,300))
        XCTAssertEqual(h.view(turnID:"a").recent.first?.generationSeconds,30)
        XCTAssertEqual(h.view(turnID:"a").average,20)
    }
    func testMissingOrInvalidArgumentTimingNeverFallsBackToUsageTime() {
        var h = PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","r",100,110,"Reasoning"));h.ingest(call("args",120))
        h.ingest(record("a","reply",180,1000,900))
        h.resolveTiming { _ in nil };XCTAssertNil(h.view(turnID:"a").average)
        h.resolveTiming { _ in 125 };XCTAssertNil(h.view(turnID:"a").average)
    }
    func testLargeToolArgumentsAreStrippedAndCompletionIdentityPreserved() throws {
        let line = Data((#"{"timestamp":"2026-10-19T00:00:00Z","ordinal":1,"type":"response_item","payload":{"type":"custom_tool_call","id":"args","input":""# + String(repeating:"PRIVATE_ARGUMENTS",count:100000) + #""}}"#).utf8)
        let decoded = try XCTUnwrap(LogRecordDecoder.decode(line))
        let p = try XCTUnwrap(decoded["payload"] as? [String:Any])
        XCTAssertEqual(p["id"] as? String,"args");XCTAssertNil(p["input"])
    }

    func testReorderedSmallItemDoesNotLoseCompletionTimestamp() throws {
        let line=Data(#"{"type":"event_msg","payload":{"type":"item_completed","turn_id":"a","item":{"type":"Reasoning","id":"r"},"completed_at_ms":110000,"started_at_ms":100000}}"#.utf8)
        let decoded=try XCTUnwrap(LogRecordDecoder.decode(line))
        let p=try XCTUnwrap(decoded["payload"] as? [String:Any])
        XCTAssertEqual(p["completed_at_ms"] as? Int,110000)
        XCTAssertEqual(p["started_at_ms"] as? Int,100000)
    }

    func testBodyUsesOfficialNonReasoningTokensAndOnlyBodyIntervals() {
        var h=PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","r",100,110,"Reasoning"));h.ingest(item("a","m",120,125))
        h.ingest(record("a","reply",130,500,300))
        let v=h.view(turnID:"a")
        XCTAssertEqual(v.bodyAverage,40)
        XCTAssertEqual(v.body.first?.tokens,200)
        XCTAssertEqual(v.recent.first?.outputTokens,500)
        XCTAssertEqual(v.recent.first?.generationSeconds,15)
    }
    func testToolArgumentsNeverMislabelledAsBodyEvenWhenVisibleTextExists() {
        var h=PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","r",100,110,"Reasoning"));h.ingest(item("a","m",110,115))
        h.ingest(call("args",120));h.ingest(record("a","reply",125,1000,300))
        XCTAssertNil(h.view(turnID:"a").bodyAverage)
        h.resolveTiming { _ in 115 }
        XCTAssertEqual(h.view(turnID:"a").average,50)
        XCTAssertNil(h.view(turnID:"a").bodyAverage)
    }
    func testBodyResultPersistsAcrossToolRequestsSerializationAndModelChanges() throws {
        var h=PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","m",100,110));h.ingest(record("a","body",120,200))
        for n in 0..<12 {
            let t=Double(130+n*20)
            h.ingest(item("a","reason\(n)",t,t+10,"Reasoning"));h.ingest(call("args\(n)",t+15))
            h.ingest(record("a","tool\(n)",t+16,500,300));h.resolveTiming { _ in t+10 }
        }
        h.ingest(record("a","tool11",366,500,300)) // duplicate does not add samples
        h=try JSONDecoder().decode(PerformanceHistory.self,from:JSONEncoder().encode(h))
        let v=h.view(turnID:"a")
        XCTAssertEqual(v.body.count,1);XCTAssertEqual(v.bodyAverage,20)
        h.ingest(context("b","other"));XCTAssertNil(h.view(turnID:"b").bodyAverage)
        h.ingest(context("c"));XCTAssertEqual(h.view(turnID:"c").bodyAverage,20)
    }
    func testNoTimedReasoningCannotCreateReasoningSpeed() {
        var h=PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","m",100,110));h.ingest(record("a","r",120,500,300))
        XCTAssertNil(h.view(turnID:"a").bodyAverage)
    }

    func testCollapsedReasoningCannotInflateCombinedSpeedButBodyIsStillMeasurable() {
        var h=PerformanceHistory();h.ingest(context("a"))
        h.ingest(item("a","r",100,100.001,"Reasoning"));h.ingest(item("a","m",110,120))
        h.ingest(record("a","reply",125,500,300))
        XCTAssertNil(h.view(turnID:"a").average)
        XCTAssertEqual(h.view(turnID:"a").bodyAverage,20)
    }

}
