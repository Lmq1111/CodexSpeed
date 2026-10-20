import AppKit
import Combine
import MonitorCore

@MainActor final class AppModel: ObservableObject {
    @Published var metrics = Metrics()
    @Published var connection: ConnectionState = .connecting
    @Published var conversations: [Conversation] = []
    @Published var selected: Conversation?
    @Published var pinnedID: String?
    @Published var resolution = Resolution(conversation: nil, source: "正在识别当前对话", trusted: false, away: false)
    @Published var chooser = false
    @Published var infoVisible = false
    @Published var previous = false
    @Published var panelVisible = false
    @Published var error: String?
    @Published var search = ""
    let resolver = ConversationResolver()
    let service = MonitorService()
    var onMenuUpdate: ((String) -> Void)?
    private let defaults = UserDefaults.standard
    private let catalogQueue = DispatchQueue(label: "CodexSpeed.catalog", qos: .utility)
    private var catalogTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var latestMetrics = Metrics()
    private var diagnosticAt = Date.distantPast
    private var maxDeliveryLagMs = 0.0
    private let diagnostics = CommandLine.arguments.contains("--diagnostics")
    var isPinned: Bool { pinnedID != nil }
    var displayedResult: TurnResult? { previous ? metrics.performance.previous : metrics.performance.current }
    var usage: Usage? { displayedResult?.usage ?? (previous ? metrics.previousUsage : metrics.currentUsage) }
    var knownCurrent: Bool { isPinned || resolution.conversation != nil }
    var modeLabel: String { isPinned ? "已固定此对话" : resolution.away && resolution.conversation != nil ? "跟随 · 保留最后查看" : "跟随当前对话" }
    var status: String { connection != .connected ? connection.label : metrics.phase.rawValue }
    var menuText: String {
        guard selected != nil else { return "待选择" }
        let text: String
        if let speed = latestMetrics.performance.bodyAverage {
            text = "≈ \(Int(speed.rounded())) tok/s"
        } else {
            text = latestMetrics.performance.loading ? "加载中" : "待采样"
        }
        return text + (connection == .connected ? "" : " ·")
    }
    static let combinedUnavailableReason = "官方输出包含推理 token，但当前事件无法确认完整思考耗时；综合均速暂不可测。"

    func start() {
        pinnedID = defaults.string(forKey: "pinnedConversation")
        service.onUpdate = { [weak self] metrics, connection in
            DispatchQueue.main.async {
                guard let self, metrics.conversationID == self.selected?.id else { return }
                if metrics.revision != self.latestMetrics.revision, metrics.eventCount > 1, let received = metrics.lastEvent { self.maxDeliveryLagMs = max(self.maxDeliveryLagMs, Date().timeIntervalSince(received) * 1000) }
                self.latestMetrics = metrics
                // Keep the menu live while avoiding closed-panel chart invalidations.
                if self.panelVisible { self.metrics = metrics }
                if self.connection != connection { self.connection = connection }
                self.onMenuUpdate?(self.menuText)
                self.writeDiagnostic(metrics)
            }
        }
        service.onError = { [weak self] message in DispatchQueue.main.async { self?.error = message } }
        resolver.onResolution = { [weak self] result in
            guard let self else { return }
            if self.resolution.conversation?.id != result.conversation?.id || self.resolution.source != result.source || self.resolution.trusted != result.trusted || self.resolution.away != result.away || self.resolution.diagnostic != result.diagnostic { self.resolution = result }
            if !self.isPinned { self.setSelected(result.conversation) }
        }
        refreshCatalog(); resolver.start(); service.start()
        catalogTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshCatalog() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.service.reconnect(); self?.refreshCatalog(); self?.resolver.poll() } }
    }
    func refreshCatalog() {
        catalogQueue.async { [weak self] in
            do { let rows = try ConversationCatalog.read(); DispatchQueue.main.async { self?.acceptCatalog(rows) } }
            catch { DispatchQueue.main.async { self?.error = "无法读取对话目录：\(error.localizedDescription)" } }
        }
    }
    private func acceptCatalog(_ rows: [Conversation]) {
        if conversations != rows { conversations = rows; resolver.setCatalog(rows) }
        if let pinnedID {
            if let row = rows.first(where: { $0.id == pinnedID }) { setSelected(row) }
            else { setSelected(nil); error = "固定的对话暂不可用，可恢复跟随或重新选择。" }
        }
    }
    private func setSelected(_ value: Conversation?) {
        guard selected != value else { return }
        if selected?.id == value?.id && selected?.hostId == value?.hostId { selected = value; return }
        selected = value; previous = false; infoVisible = false; metrics = Metrics(); latestMetrics = Metrics(); service.select(value)
        onMenuUpdate?(menuText)
    }
    func pin(_ conversation: Conversation) {
        pinnedID = conversation.id; defaults.set(conversation.id, forKey: "pinnedConversation"); error = nil
        setSelected(conversation); chooser = false; onMenuUpdate?(menuText)
    }
    func follow() {
        pinnedID = nil; defaults.removeObject(forKey: "pinnedConversation"); error = nil; chooser = false
        setSelected(resolution.conversation); resolver.poll(); onMenuUpdate?(menuText)
    }
    func togglePin() { if isPinned { follow() } else if let selected { pin(selected) } }
    func showPanel() { metrics = latestMetrics; panelVisible = true; resolver.poll(); refreshCatalog() }
    func hidePanel() { panelVisible = false; chooser = false; infoVisible = false }
    func stop() { service.stop() }
    private func writeDiagnostic(_ m: Metrics) {
        guard diagnostics, Date().timeIntervalSince(diagnosticAt) >= 1 else { return }; diagnosticAt = Date()
        let value: [String: Any] = ["at": Date().timeIntervalSince1970, "threadId": selected?.id ?? "", "resolvedThreadId": resolution.conversation?.id ?? "", "pinned": isPinned, "panelVisible": panelVisible, "source": resolution.source, "resolverDiagnostic": resolution.diagnostic, "accessibility": resolution.trusted, "connection": connection.label, "phase": m.phase.rawValue, "events": m.eventCount, "maxDeliveryLagMs": maxDeliveryLagMs, "revision": m.revision, "speed": m.speed as Any? ?? NSNull(), "average": NSNull(), "averageUnavailableReason": Self.combinedUnavailableReason, "bodyAverage": m.performance.bodyAverage as Any? ?? NSNull(), "bodySamples": m.performance.body.count, "performanceModel": m.performance.model, "historyLoading": m.performance.loading, "previousDuration": m.performance.previous?.duration as Any? ?? NSNull(), "previousAverage": NSNull(), "tokens": m.sampledTokens, "turnId": m.turnId as Any? ?? NSNull(), "turnTotal": m.currentUsage?.total as Any? ?? NSNull(), "previousTotal": m.previousUsage?.total as Any? ?? NSNull(), "threadTotal": m.totalUsage?.total as Any? ?? NSNull()]
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexSpeed")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { try? data.write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic) }
    }
}
