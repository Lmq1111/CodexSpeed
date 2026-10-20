import Foundation

public final class MonitorService: @unchecked Sendable {
    public var onUpdate: ((Metrics, ConnectionState) -> Void)?
    public var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "CodexSpeed.metrics", qos: .userInitiated)
    private let client = DesktopIPCClient()
    private var reducer = StreamReducer()
    private var engine: MetricsEngine?
    private var counter: LocalTokenizer?
    private var logs: UsageLogReader?
    private var selected: Conversation?
    private var connection: ConnectionState = .connecting
    private var ready = false
    private var timer: DispatchSourceTimer?
    private var hasSnapshot = false
    private var subscribedAt: Double = 0
    public init() {}
    public func start() {
        client.onMessage = { [weak self] message in self?.queue.async { self?.receive(message) } }
        client.onStatus = { [weak self] status in self?.queue.async {
            guard let self else { return }; self.connection = status
            if status != .connected { self.hasSnapshot = false; self.engine?.disconnect() } else { self.subscribedAt = ProcessInfo.processInfo.systemUptime }
            self.publish()
        } }
        queue.async { [self] in
            do { counter = try LocalTokenizer(); engine = MetricsEngine(counter: counter!); ready = true }
            catch { onError?("分词词表加载失败：\(error.localizedDescription)"); return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(30))
            source.setEventHandler { [weak self] in self?.tick() }; timer = source; source.resume(); client.start()
        }
    }
    public func select(_ conversation: Conversation?) {
        queue.async { [self] in
            if selected?.id == conversation?.id && selected?.hostId == conversation?.hostId { return }
            selected = conversation; reducer = StreamReducer(); hasSnapshot = false; subscribedAt = ProcessInfo.processInfo.systemUptime
            if let counter { engine = MetricsEngine(counter: counter) }
            logs?.saveCache()
            logs = conversation.map {
                let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexSpeed/usage-v5")
                let name = Data(($0.hostId + ":" + $0.id).utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
                return UsageLogReader(path: $0.rollout, cacheURL: directory.appendingPathComponent(name + ".json"), timings: RuntimeItemTimingReader(threadID: $0.id))
            }
            client.select(conversation); tick()
        }
    }
    public func reconnect() { queue.async { [self] in hasSnapshot = false; engine?.disconnect(); subscribedAt = ProcessInfo.processInfo.systemUptime; client.resynchronize() } }
    public func stop() { client.stop(); queue.async { [self] in timer?.cancel(); timer = nil; logs?.saveCache() } }
    private func receive(_ message: [String: Any]) {
        guard let selected, let params = message["params"] as? [String: Any], params["conversationId"] as? String == selected.id,
              params["hostId"] as? String == selected.hostId, let change = params["change"] as? [String: Any] else { return }
        do {
            let snapshot = change["type"] as? String == "snapshot"
            if !hasSnapshot && !snapshot { return }
            guard try reducer.apply(change) else { return }
            hasSnapshot = true
            engine?.update(state: reducer.state, snapshot: snapshot, revision: reducer.revision)
            if let logs, logs.isCaughtUp { engine?.applyLogs(logs.summary) }
        } catch {
            hasSnapshot = false; engine?.disconnect(); reducer = StreamReducer(); client.resynchronize(); subscribedAt = ProcessInfo.processInfo.systemUptime
        }
    }
    private func tick() {
        guard ready else { return }
        if let logs { logs.poll(); if logs.isCaughtUp { engine?.applyLogs(logs.summary) } }
        engine?.tick()
        // A connected socket without a conversation snapshot is not a live subscription.
        if selected != nil && connection == .connected && !hasSnapshot && ProcessInfo.processInfo.systemUptime - subscribedAt > 8 {
            subscribedAt = ProcessInfo.processInfo.systemUptime; client.resynchronize()
        }
        publish()
    }
    private func publish() {
        var state = connection
        if connection == .connected && selected != nil && !hasSnapshot { state = .connecting }
        var metrics = engine?.metrics ?? Metrics()
        metrics.conversationID = selected?.id
        if let logs {
            metrics.performance = logs.summary.performance.view(turnID: metrics.turnId, fallbackModel: selected?.model ?? "")
            metrics.performance.loading = !logs.isCaughtUp
            if let result = metrics.performance.current, let duration = result.duration { metrics.elapsed = duration }
        }
        onUpdate?(metrics, state)
    }
}
