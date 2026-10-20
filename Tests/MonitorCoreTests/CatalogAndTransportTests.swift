import XCTest
import CSQLite
import Darwin
@testable import MonitorCore

final class CatalogTests: XCTestCase {
    func testDisplayNameOverridesInitialPromptAndEmptyNameFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE threads(id TEXT,title TEXT,name TEXT,cwd TEXT,rollout_path TEXT,model TEXT,archived INTEGER,updated_at INTEGER);
        INSERT INTO threads VALUES('a','用户最初的问题','显示的会话标题','/project','','gpt',0,2);
        INSERT INTO threads VALUES('b','旧版标题','','/project','','gpt',0,1);
        INSERT INTO threads VALUES('c','归档标题','归档标题','/project','','gpt',1,3);
        """
        XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK)
        let rows = try ConversationCatalog.read(home:directory)
        XCTAssertEqual(rows.map(\.title),["显示的会话标题","旧版标题"])
    }
    func testBusyCatalogCanRecoverWithoutChangingTheDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE threads(id TEXT,title TEXT,name TEXT,cwd TEXT,rollout_path TEXT,model TEXT,archived INTEGER,updated_at INTEGER); BEGIN EXCLUSIVE;", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try ConversationCatalog.read(home: directory)) { error in
            let failure = error as? ConversationCatalog.CatalogError
            XCTAssertEqual(failure?.code, SQLITE_BUSY)
            XCTAssertTrue(error.localizedDescription.contains("数据库正忙"))
            XCTAssertFalse(failure?.detail.isEmpty ?? true)
        }
        XCTAssertEqual(sqlite3_exec(db, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try ConversationCatalog.read(home: directory), [])
    }

    func testSchemaFailureIncludesSQLiteDetails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        sqlite3_close(db)
        XCTAssertThrowsError(try ConversationCatalog.read(home: directory)) { error in
            let failure = error as? ConversationCatalog.CatalogError
            XCTAssertEqual(failure?.code, SQLITE_ERROR)
            XCTAssertTrue(error.localizedDescription.contains("查询对话目录失败"))
            XCTAssertTrue(failure?.detail.contains("threads") == true)
        }
    }

}

final class TransportTests: XCTestCase {
    func testSocketHandshakeSubscriptionAndReadOnlyDiscovery() throws {
        let path = NSTemporaryDirectory() + "speed-" + UUID().uuidString.prefix(8) + ".sock"
        let fd = socket(AF_UNIX,SOCK_STREAM,0)
        XCTAssertGreaterThanOrEqual(fd,0)
        defer { close(fd); unlink(path) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of:&address.sun_path) { d in bytes.withUnsafeBytes { d.copyBytes(from:$0) } }
        let bound = withUnsafePointer(to:&address) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(bound,0); XCTAssertEqual(listen(fd,1),0)
        let snapshot = expectation(description:"snapshot delivered"), readOnly = expectation(description:"client refuses command handling")
        let serverDone = expectation(description:"server stopped")
        DispatchQueue.global().async {
            defer { serverDone.fulfill() }
            let peer = accept(fd,nil,nil); guard peer >= 0 else { return }; defer { close(peer) }
            var timeout=timeval(tv_sec:3,tv_usec:0); setsockopt(peer,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
            var decoder=FrameDecoder(), bytes=[UInt8](repeating:0,count:65536)
            func send(_ message:[String:Any]) {
                guard let data=try? FrameDecoder.encode(message) else { return }
                _ = data.withUnsafeBytes { Darwin.send(peer,$0.baseAddress,$0.count,0) }
            }
            var discoverySeen=false, subscribed=false
            while !discoverySeen || !subscribed {
                let n=recv(peer,&bytes,bytes.count,0); if n<=0 { break }
                for message in (try? decoder.append(Data(bytes.prefix(n)))) ?? [] {
                    if message["method"] as? String == "initialize" {
                        send(["type":"response","method":"initialize","result":["clientId":"test-client"]])
                        send(["type":"client-discovery-request","requestId":"probe"])
                    }
                    if message["method"] as? String == "thread-stream-following-changed", let p=message["params"] as? [String:Any], p["following"] as? Bool == true {
                        send(["type":"broadcast","method":"thread-stream-state-changed","version":11,"params":["conversationId":"thread","hostId":"local","change":["type":"snapshot","revision":1,"conversationState":["id":"thread"]]]])
                    }
                    if message["type"] as? String == "client-discovery-response", (message["response"] as? [String:Any])?["canHandle"] as? Bool == false { readOnly.fulfill(); discoverySeen=true }
                    if message["method"] as? String == "thread-stream-following-changed" { subscribed=true }
                }
            }
        }
        let client=DesktopIPCClient(path:path)
        client.onMessage={ m in if m["method"] as? String == "thread-stream-state-changed" { snapshot.fulfill() } }
        client.select(Conversation(id:"thread",title:"Test")); client.start()
        wait(for:[snapshot,readOnly,serverDone],timeout:5); client.stop()
    }
}
