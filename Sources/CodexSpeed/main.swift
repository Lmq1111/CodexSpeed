import AppKit
import SwiftUI
import MonitorCore

final class MonitorPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { escape?() }
}
final class ClearPanelContent: NSView {
    override var isOpaque: Bool { false }
}
final class ClearHostingView: NSHostingView<PanelView> {
    override var isOpaque: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var item: NSStatusItem!
    var panel: MonitorPanel!
    var host: NSHostingView<PanelView>!
    var scrollView: NSScrollView!
    var globalMonitor: Any?
    var localMonitor: Any?
    var sizeObserver: AnyCancellable?
    var layoutObservers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "CodexSpeed")
            button.imagePosition = .imageLeading; button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.title = " 连接中"; button.target = self; button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp]); button.toolTip = "CodexSpeed · 正文均速估算（不含推理和工具参数）；展开查看样本范围与官方用量"
            button.postsFrameChangedNotifications = true
            let anchors: [(Notification.Name, AnyObject?)] = [
                (NSView.frameDidChangeNotification, button),
                (NSWindow.didMoveNotification, button.window),
                (NSWindow.didChangeScreenNotification, button.window)
            ]
            for (name, object) in anchors {
                guard let object else { continue }
                layoutObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resizeIfNeeded() }
                })
            }
        }
        panel = MonitorPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 373), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        let root = ClearPanelContent(); root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.cornerRadius = 14; root.layer?.masksToBounds = true
        let material = NSVisualEffectView(); material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 14; material.layer?.masksToBounds = true
        material.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(material)
        host = ClearHostingView(rootView: PanelView(model: model)); host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView = NSScrollView(); scrollView.drawsBackground = false; scrollView.hasVerticalScroller = true; scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder; scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false; scrollView.documentView = host
        material.addSubview(scrollView)
        NSLayoutConstraint.activate([material.topAnchor.constraint(equalTo: root.topAnchor), material.leadingAnchor.constraint(equalTo: root.leadingAnchor), material.trailingAnchor.constraint(equalTo: root.trailingAnchor), material.bottomAnchor.constraint(equalTo: root.bottomAnchor), scrollView.topAnchor.constraint(equalTo: material.topAnchor), scrollView.leadingAnchor.constraint(equalTo: material.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: material.trailingAnchor), scrollView.bottomAnchor.constraint(equalTo: material.bottomAnchor), host.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)])
        material.layer?.borderWidth = 0.5; material.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        panel.contentView = root
        panel.escape = { [weak self] in guard let self else { return }; if self.model.infoVisible { self.model.infoVisible = false } else if self.model.chooser { self.model.chooser = false } else { self.hide() } }
        model.onMenuUpdate = { [weak self] text in
            let value = " " + text
            if self?.item.button?.title != value {
                self?.item.button?.title = value
                // Let the menu bar settle its new intrinsic width before anchoring.
                DispatchQueue.main.async { self?.resizeIfNeeded() }
            }
        }
        sizeObserver = model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.resizeIfNeeded() } }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible { self.panel.escape?(); return nil }
            if event.type != .keyDown && self.panel.isVisible && event.window !== self.panel && event.window !== self.item.button?.window { self.hide() }
            return event
        }
        model.start()
        if !UserDefaults.standard.bool(forKey: "launchedBefore") || CommandLine.arguments.contains("--show") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.show() }
        }
    }
    @objc func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            hide(); let menu = NSMenu()
            menu.addItem(withTitle: "打开监控面板", action: #selector(showAction), keyEquivalent: "").target = self
            menu.addItem(withTitle: "辅助功能设置…", action: #selector(permission), keyEquivalent: "").target = self
            menu.addItem(.separator()); menu.addItem(withTitle: "退出 CodexSpeed", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
        } else if panel.isVisible { hide() } else { show() }
    }
    @objc func showAction() { show() }
    @objc func permission() { model.resolver.requestPermission() }
    @objc func quit() { NSApp.terminate(nil) }
    func show() { model.showPanel(); resize(); panel.makeKeyAndOrderFront(nil) }
    func hide() { guard panel?.isVisible == true else { return }; panel.orderOut(nil); model.hidePanel() }
    func resizeIfNeeded() {
        guard model.panelVisible else { return }; resize()
    }
    func resize() {
        guard model.panelVisible, let button = item.button, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main!
        let width = min(360, screen.visibleFrame.width - 24)
        host.setFrameSize(NSSize(width: width, height: host.frame.height))
        let height = min(max(240, host.fittingSize.height), screen.visibleFrame.height - 24)
        let x = max(screen.visibleFrame.minX + 8, min(rect.midX - width / 2, screen.visibleFrame.maxX - width - 8))
        let y = max(screen.visibleFrame.minY + 8, min(rect.minY - 6, screen.visibleFrame.maxY) - height)
        let frame = NSRect(x: x, y: y, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.stop(); layoutObservers.forEach(NotificationCenter.default.removeObserver); if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) } }
}
import Combine

@MainActor func runProbe() {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--probe"), arguments.indices.contains(index + 1), let conversation = try? ConversationCatalog.read().first(where: { $0.id == arguments[index + 1] }) else { print("Probe requires a known local thread ID"); exit(2) }
    let service = MonitorService()
    var last = Date.distantPast
    var lastSpeed: Double?
    service.onError = { print($0); exit(1) }
    service.onUpdate = { metrics, status in
        guard Date().timeIntervalSince(last) >= 1 || metrics.speed != lastSpeed else { return }; last = Date(); lastSpeed = metrics.speed
        let value: [String: Any] = ["at": Date().timeIntervalSince1970, "connection": status.label, "phase": metrics.phase.rawValue, "events": metrics.eventCount, "revision": metrics.revision, "speed": metrics.speed as Any? ?? NSNull(), "tokens": metrics.sampledTokens, "turnTotal": metrics.currentUsage?.total as Any? ?? NSNull(), "threadTotal": metrics.totalUsage?.total as Any? ?? NSNull()]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print(line); fflush(stdout) }
    }
    service.start(); service.select(conversation)
    let secondsIndex = arguments.firstIndex(of: "--seconds")
    let seconds = secondsIndex.flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 15
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { service.stop(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) } }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--probe") { MainActor.assumeIsolated { runProbe() } }
else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
