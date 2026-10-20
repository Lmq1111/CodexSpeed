import XCTest
import Darwin
@testable import MonitorCore

private final class TestSocketServer: @unchecked Sendable {
    let path = NSTemporaryDirectory() + "speed-" + UUID().uuidString.prefix(8) + ".sock"
    let fd: Int32
    init() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of:&address.sun_path) { d in bytes.withUnsafeBytes { d.copyBytes(from:$0) } }
        let result = withUnsafePointer(to:&address) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, listen(fd,2) == 0 else { throw POSIXError(.EADDRINUSE) }
    }
    deinit { close(fd); unlink(path) }
    func serve(connections: Int, handler: @escaping (Int, [String:Any], Int32) -> Bool) {
        DispatchQueue.global().async { [self] in
            for connection in 0..<connections {
                var pollFD = pollfd(fd:fd,events:Int16(POLLIN),revents:0)
                guard poll(&pollFD,1,5000) > 0 else { return }
                let peer = accept(fd,nil,nil); guard peer >= 0 else { return }
                var timeout=timeval(tv_sec:3,tv_usec:0); setsockopt(peer,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                var noSignal:Int32=1; setsockopt(peer,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
                var decoder=FrameDecoder(), buffer=[UInt8](repeating:0,count:65536), keep=true
                while keep {
                    let n=recv(peer,&buffer,buffer.count,0); if n<=0 { break }
                    for message in (try? decoder.append(Data(buffer.prefix(n)))) ?? [] {
                        if message["method"] as? String == "initialize" {
                            Self.send(["type":"response","method":"initialize","result":["clientId":"test-\(connection)"]],to:peer)
                        } else if !handler(connection,message,peer) { keep=false; break }
                    }
                }
                close(peer)
            }
        }
    }
    static func send(_ message:[String:Any],to peer:Int32) {
        let data=try! FrameDecoder.encode(message)
        _=data.withUnsafeBytes { Darwin.send(peer,$0.baseAddress,$0.count,0) }
    }
}
final class ReconnectionTests: XCTestCase {
    func testReconnectRestoresSelectedSubscription() throws {
        let server=try TestSocketServer()
        let probe=DesktopIPCClient(path:server.path)
        let received=expectation(description:"two snapshots"); received.expectedFulfillmentCount=2
        let disconnected=expectation(description:"connection interruption")
        server.serve(connections:2) { number,message,peer in
            guard message["method"] as? String == "thread-stream-following-changed", let p=message["params"] as? [String:Any], p["following"] as? Bool == true else { return true }
            XCTAssertEqual(p["conversationId"] as? String,"chosen")
            TestSocketServer.send(["type":"broadcast","method":"thread-stream-state-changed","version":11,"params":["conversationId":"chosen","hostId":"local","change":["type":"snapshot","revision":number+1,"conversationState":["id":"chosen"]]]],to:peer)
            return false
        }
        var snapshots=0
        probe.onMessage={ _ in snapshots += 1; received.fulfill(); if snapshots == 2 { probe.stop() } }
        probe.onStatus={ state in if state == .disconnected && snapshots == 1 { disconnected.fulfill() } }
        probe.select(Conversation(id:"chosen",title:"Test")); probe.start()
        wait(for:[received,disconnected],timeout:7); probe.stop()
        withExtendedLifetime(server) {}
    }
    func testUnsupportedProtocolIsReportedInsteadOfInventingLiveData() throws {
        let server=try TestSocketServer()
        let client=DesktopIPCClient(path:server.path)
        let unsupported=expectation(description:"incompatible protocol")
        server.serve(connections:1) { _,message,peer in
            guard message["method"] as? String == "thread-stream-following-changed" else { return true }
            TestSocketServer.send(["type":"broadcast","method":"thread-stream-state-changed","version":999,"params":[:]],to:peer)
            return false
        }
        client.onStatus={ state in if state == .incompatible { unsupported.fulfill(); client.stop() } }
        client.onMessage={ _ in XCTFail("Unsupported data must not reach the reducer") }
        client.select(Conversation(id:"chosen",title:"Test")); client.start()
        wait(for:[unsupported],timeout:4); client.stop(); withExtendedLifetime(server) {}
    }
}
