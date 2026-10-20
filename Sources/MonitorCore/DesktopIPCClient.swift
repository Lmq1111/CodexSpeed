import Foundation
import Darwin

public enum ConnectionState: Equatable, Sendable {
    case connecting, connected, disconnected, incompatible
    public var label: String {
        switch self { case .connecting: "正在连接"; case .connected: "实时连接"; case .disconnected: "连接断开 · 仅日志"; case .incompatible: "协议不兼容 · 仅日志" }
    }
}
public final class DesktopIPCClient: @unchecked Sendable {
    public var onMessage: (([String: Any]) -> Void)?
    public var onStatus: ((ConnectionState) -> Void)?
    private let queue = DispatchQueue(label: "CodexSpeed.ipc", qos: .utility)
    private let lock = NSLock()
    private var desired: Conversation?
    private var generation = 0
    private var stopped = false
    private var started = false
    private let path: String
    public init(path: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/ipc/ipc.sock").path) { self.path = path }
    public func select(_ conversation: Conversation?) { lock.lock(); desired = conversation; generation += 1; lock.unlock() }
    public func resynchronize() { lock.lock(); generation += 1; lock.unlock() }
    public func stop() { lock.lock(); stopped = true; lock.unlock() }
    public func start() {
        lock.lock(); guard !started else { lock.unlock(); return }; started = true; lock.unlock()
        queue.async { [self] in run() }
    }
    private func configuration() -> (Conversation?, Int, Bool) { lock.lock(); defer { lock.unlock() }; return (desired, generation, stopped) }
    private func pause(_ seconds: Double) { let end = ProcessInfo.processInfo.systemUptime + seconds; while !configuration().2 && ProcessInfo.processInfo.systemUptime < end { usleep(100_000) } }
    private func run() {
        var delay = 1.0
        while !configuration().2 {
            onStatus?(.connecting)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { onStatus?(.disconnected); pause(delay); delay = min(30, delay * 2); continue }
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8CString)
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); onStatus?(.incompatible); return }
            withUnsafeMutableBytes(of: &address.sun_path) { dest in bytes.withUnsafeBytes { dest.copyBytes(from: $0) } }
            let connected = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } } == 0
            guard connected else { close(fd); onStatus?(.disconnected); pause(delay); delay = min(30, delay * 2); continue }
            var noSignal: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 0, tv_usec: 250_000); setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)); setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var client: String?, active: Conversation?, activeGeneration = -1, decoder = FrameDecoder(), protocolFailure = false
            let handshakeAt = ProcessInfo.processInfo.systemUptime
            func send(_ object: [String: Any]) throws {
                let data = try FrameDecoder.encode(object)
                try data.withUnsafeBytes { buffer in
                    var sent = 0
                    while sent < buffer.count {
                        let n = Darwin.send(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                        if n <= 0 { throw POSIXError(.EPIPE) }; sent += n
                    }
                }
            }
            func follow(_ conversation: Conversation, _ following: Bool) throws {
                guard let client else { return }
                try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1, "sourceClientId": client, "params": ["conversationId": conversation.id, "hostId": conversation.hostId, "following": following]])
            }
            do {
                try send(["type": "request", "requestId": UUID().uuidString, "sourceClientId": "initializing-client", "version": 0, "method": "initialize", "params": ["clientType": "codex-speed-monitor"]])
                var bytes = [UInt8](repeating: 0, count: 65536)
                while !configuration().2 {
                    let (target, version, _) = configuration()
                    if client != nil && version != activeGeneration {
                        if let active { try follow(active, false) }
                        active = target; activeGeneration = version
                        if let target { try follow(target, true) }
                    }
                    if client == nil && ProcessInfo.processInfo.systemUptime - handshakeAt > 5 { throw POSIXError(.ETIMEDOUT) }
                    let count = recv(fd, &bytes, bytes.count, 0)
                    if count == 0 { break }
                    if count < 0 { if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }; break }
                    for message in try decoder.append(Data(bytes.prefix(count))) {
                        let method = message["method"] as? String
                        if message["type"] as? String == "response" && method == "initialize" {
                            guard let result = message["result"] as? [String: Any], let id = result["clientId"] as? String else { throw StreamError.incompatibleVersion }
                            client = id; delay = 1; onStatus?(.connected)
                        } else if message["type"] as? String == "client-discovery-request", let id = message["requestId"] {
                            try send(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]])
                        } else if method == "thread-stream-state-changed" {
                            guard message["version"] as? Int == 11 else { throw StreamError.incompatibleVersion }
                            onMessage?(message)
                        } else if method == "ipc-connection-reset" { throw POSIXError(.ECONNRESET) }
                    }
                }
            } catch StreamError.incompatibleVersion { protocolFailure = true } catch {}
            if let active { try? follow(active, false) }
            close(fd)
            if configuration().2 { break }
            onStatus?(protocolFailure ? .incompatible : .disconnected)
            pause(protocolFailure ? 30 : delay); delay = min(30, delay * 2)
        }
    }
}
