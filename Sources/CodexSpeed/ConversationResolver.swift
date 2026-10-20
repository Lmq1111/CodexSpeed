import AppKit
import ApplicationServices
import MonitorCore

struct Resolution {
    var conversation: Conversation?
    var source: String
    var trusted: Bool
    var away: Bool
    var diagnostic: String = ""
}
final class ConversationResolver {
    var onResolution: ((Resolution) -> Void)?
    private let queue = DispatchQueue(label: "CodexSpeed.focus", qos: .utility)
    private var busy = false
    private var last: Conversation?
    private static var trace = ""
    private static var cachedWindow: AXUIElement?
    private static var cachedHeader: AXUIElement?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var catalog: [Conversation] = []
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.poll() }
        poll()
    }
    func setCatalog(_ values: [Conversation]) { catalog = values; poll() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func poll() {
        guard !busy else { return }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let isCodex = front.bundleIdentifier == "com.openai.codex"
        let trusted = AXIsProcessTrusted()
        if !isCodex { onResolution?(Resolution(conversation: last, source: last == nil ? "尚未识别当前对话" : "保留最后查看", trusted: trusted, away: true)); return }
        guard trusted else { onResolution?(Resolution(conversation: nil, source: "需要辅助功能权限", trusted: false, away: false)); return }
        installObserver(pid: front.processIdentifier)
        busy = true
        let pid = front.processIdentifier, rows = catalog
        queue.async { [weak self] in
            let result = Self.readFocused(pid: pid, catalog: rows)
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if let result { self.last = result.0 }
                self.onResolution?(Resolution(conversation: result?.0, source: result?.1 ?? "无法识别当前对话", trusted: true, away: false, diagnostic: Self.trace))
            }
        }
    }
    private func installObserver(pid: pid_t) {
        guard observedPID != pid else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedPID = pid
        var next: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let owner = Unmanaged<ConversationResolver>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.poll() }
        }
        guard AXObserverCreate(pid, callback, &next) == .success, let next else { return }
        observer = next
        let app = AXUIElementCreateApplication(pid)
        for notification in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXTitleChangedNotification] {
            AXObserverAddNotification(next, app, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }; return value
    }
    private static func strings(_ element: AXUIElement) -> [String] {
        ["AXTitle", "AXDescription", "AXValue", "AXURL", "AXDocument", "AXIdentifier"].compactMap { name in
            let v = attribute(element, name)
            if let s = v as? String, !s.isEmpty, s.count < 1000 { return s }
            if let u = v as? URL { return u.absoluteString }
            return nil
        }
    }
    private static func id(from values: [String]) -> String? {
        // Accept only explicit route/identifier values, never arbitrary text containing a UUID.
        let expression = try! NSRegularExpression(pattern: #"(?:/local/|/threads/|/thread/|/conversations/|conversation[:=/-]|thread[:=/-])([0-9a-fA-F-]{36})(?:$|[/?#\s])"#)
        for value in values {
            let range = NSRange(value.startIndex..., in: value)
            if let match = expression.firstMatch(in: value, range: range), let r = Range(match.range(at: 1), in: value), UUID(uuidString: String(value[r])) != nil { return String(value[r]).lowercased() }
        }
        return nil
    }
    private static func visibleSize(_ element: AXUIElement) -> Bool {
        guard let value = attribute(element, "AXSize"), CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return false }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) && size.width > 0 && size.height > 0
    }
    private static func point(_ element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, "AXPosition"), CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }
    private static func readFocused(pid: pid_t, catalog: [Conversation]) -> (Conversation, String)? {
        let application = AXUIElementCreateApplication(pid)
        trace = "正在读取焦点窗口"
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let raw = attribute(application, kAXFocusedWindowAttribute), CFGetTypeID(raw as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        let window = raw as! AXUIElement
        let origin = point(window)
        func headerMatch(_ element: AXUIElement) -> Conversation? {
            guard let origin, let position = point(element), position.y >= origin.y,
                  position.y < origin.y + 64, visibleSize(element) else { return nil }
            let matches = strings(element).compactMap { value in
                SelectionResolver.resolve(explicitID: nil, title: value, project: nil, conversations: catalog)
            }
            let unique = Dictionary(grouping: matches, by: \.id)
            return unique.count == 1 ? unique.values.first?.first : nil
        }
        if let cachedWindow, CFEqual(cachedWindow, window), let cachedHeader, let match = headerMatch(cachedHeader) {
            trace = "focused-window-header cached element"
            return (match, "辅助功能 · 顶部会话标题")
        }
        cachedHeader = nil; cachedWindow = window
        let windowValues = strings(window)
        if let explicit = id(from: windowValues), let match = catalog.first(where: { $0.id == explicit }) { return (match, "辅助功能 · 对话 ID") }
        for value in windowValues {
            let title = value.replacingOccurrences(of: " — Codex", with: "").replacingOccurrences(of: " - Codex", with: "")
            if let match = SelectionResolver.resolve(explicitID: nil, title: title, project: nil, conversations: catalog) { return (match, "辅助功能 · 窗口标题") }
        }
        var pending: [(AXUIElement, Int)] = [(window, 0)], cursor = 0
        var matches: [(Conversation, AXUIElement)] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.45
        while cursor < pending.count, cursor < 600, ProcessInfo.processInfo.systemUptime < deadline {
            let (element, depth) = pending[cursor]; cursor += 1
            let role = attribute(element, "AXRole") as? String ?? ""
            // Only the top chrome is relevant. Never descend into conversation content or sidebar rows.
            if let origin, let position = point(element), position.y >= origin.y + 64,
               role != "AXWindow" && role != "AXWebArea" { continue }
            if ["AXStaticText", "AXHeading", "AXButton"].contains(role), let match = headerMatch(element) { matches.append((match, element)) }
            if role == "AXWebArea", let explicit = id(from: strings(element)), let match = catalog.first(where: { $0.id == explicit }) { return (match, "辅助功能 · 当前页面") }
            if depth < 50, !["AXStaticText", "AXTextArea"].contains(role), let children = attribute(element, "AXChildren") as? [AXUIElement] {
                pending += children.map { ($0, depth + 1) }
            }
        }
        let unique = Dictionary(grouping: matches, by: { $0.0.id })
        trace = "focused-window-header candidates=\(unique.count); visited=\(cursor)"
        guard unique.count == 1, let match = unique.values.first?.first else { return nil }
        cachedHeader = match.1
        return (match.0, "辅助功能 · 顶部会话标题")
    }
}
