import AppKit
import ServiceManagement
import SwiftUI

/// A menu bar item and its drop-down. `LSUIElement` keeps it out of the Dock, and nothing but the item
/// exists until the drop-down opens.
@main @MainActor final class MenuBarApp: NSObject, NSApplicationDelegate {
    static func main() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-panel"), CommandLine.arguments.indices.contains(index + 1) {
            return PanelView.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        #endif
        let app = NSApplication.shared, delegate = MenuBarApp()
        app.delegate = delegate; app.run()
    }
    private let store = MacStore.standard()
    private var item: NSStatusItem!
    private var panel: DropPanel?
    private var ticker: Timer?
    private var outsideClicks: Any?
    private var toggledAt = Date.distantPast
    private lazy var symbols = [false: symbol("timer"), true: symbol("stopwatch")]
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOver() { return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Ice, Thaw and Bartender recognise an item by these fixed names, so it keeps its section across launches.
        item.autosaveName = "SimpleTimer"
        guard let button = item.button else { return }
        button.setAccessibilityIdentifier("SimpleTimer"); button.setAccessibilityLabel("SimpleTimer")
        button.imagePosition = .imageOnly
        button.target = self; button.action = #selector(clicked)
        // Managers open a hidden item with a synthetic click or an accessibility press; act on mouse up for both buttons.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        store.changed = { [weak self] in self?.update() }
        store.refresh()
        item.isVisible = true
    }
    /// Opening the app again from Finder or Spotlight shows the drop-down, even when its item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel == nil && item != nil { open() }
        return false
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        // Managers move items with ⌘-drags, and Thaw can follow a synthetic click with a second mouse up.
        guard event?.modifierFlags.contains(.command) != true, Date().timeIntervalSince(toggledAt) > 0.3 else { return }
        toggledAt = Date()
        if event?.type == .rightMouseUp || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true) { return showMenu() }
        if panel == nil { open() } else { close() }
    }
    private func open() {
        store.tick()
        let panel = DropPanel(), host = NSHostingView(rootView: PanelView(store: store))
        panel.contentView = host
        let screens = NSScreen.screens.map(MenuBarScreen.init)
        panel.place(PanelPlacement.frame(size: host.fittingSize, item: item.button?.window?.frame, mouse: NSEvent.mouseLocation, screens: screens))
        panel.onClose = { [weak self] in self?.close() }
        panel.onSpace = { [weak self] in guard let store = self?.store else { return }; store.act(store.state.session.primaryAction) }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
    private func close() {
        guard let panel else { return }
        self.panel = nil; toggledAt = Date()
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil; store.commitDraft()
        panel.onClose = nil; panel.orderOut(nil)
        // Release SwiftUI with the panel, so a closed drop-down holds no view memory.
        panel.contentView = nil
    }
    private func showMenu() {
        close()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let menu = NSMenu()
        menu.items = [login, .separator(), NSMenuItem(title: "Quit SimpleTimer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")]
        // Attach the menu for this click only, so a left click keeps opening the drop-down.
        item.menu = menu; item.button?.performClick(nil); item.menu = nil
    }
    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do { try service.status == .enabled ? service.unregister() : service.register() } catch { return SMAppService.openSystemSettingsLoginItems() }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// The time is drawn into the item's image rather than its title. A changing title would rename the item
    /// for accessibility, which is how menu bar managers tell items apart.
    private func update() {
        let session = store.state.session, button = item.button
        if session.isActive {
            let shown = session.isUntimed ? TimerState.clock(session.elapsed(at: store.now), roundsUp: false) : TimerState.clock(session.remaining(at: store.now))
            button?.image = label(symbols[session.isUntimed]!, shown); button?.setAccessibilityValue(shown)
        } else {
            button?.image = symbols[session.isUntimed]; button?.setAccessibilityValue(nil)
        }
        button?.appearsDisabled = session.phase == .paused
        // Tick only while running: idle and paused sessions cost no wakeups.
        if session.phase != .running { ticker?.invalidate(); ticker = nil }
        else if ticker == nil {
            // Fire just after each shown second changes. Tolerance lets macOS group the wakeups.
            let lead = session.remaining(at: Date()).truncatingRemainder(dividingBy: 1)
            let timer = Timer(fire: Date(timeIntervalSinceNow: lead + 0.02), interval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.tick(); self?.update() }
            }
            timer.tolerance = 0.1; RunLoop.main.add(timer, forMode: .common); ticker = timer
        }
    }
    private func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "SimpleTimer")!
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))!
        image.isTemplate = true
        return image
    }
    /// Monospaced digits keep the item the same width from second to second.
    private func label(_ symbol: NSImage, _ time: String) -> NSImage {
        let text = NSAttributedString(string: time, attributes: [.font: font]), textSize = text.size(), spacing: CGFloat = 4
        let size = NSSize(width: ceil(symbol.size.width + spacing + textSize.width), height: max(symbol.size.height, ceil(textSize.height)))
        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: (size.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            text.draw(at: NSPoint(x: symbol.size.width + spacing, y: (size.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "SimpleTimer"
        return image
    }
    /// One copy runs at a time. A second launch shows the first copy's drop-down, then quits.
    private func handOver() -> Bool {
        guard let id = Bundle.main.bundleIdentifier,
              let first = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != getpid() }),
              let url = first.bundleURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
