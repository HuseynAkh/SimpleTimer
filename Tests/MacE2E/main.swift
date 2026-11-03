import AppKit
import SwiftUI
import UserNotifications

// End-to-end checks for the Mac menu bar app, run by scripts/test-mac-e2e.sh. The script builds this file with
// copies of the Mac and Core sources, so the real controller, panel and SwiftUI view run in-process. Checks send
// mouse and key events to the real status item and drop-down and read the drop-down through accessibility.

/// The script replaces MacStore's permission request with this counter, so no dialog appears during a run.
@MainActor enum Hooks { static var askedForAlerts = 0 }

@MainActor final class Harness {
    let app: MenuBarApp
    let scenario: String
    let file: StateFile
    let out: URL
    var results: [[String: String]] = []
    var menuTitles: [String] = []

    init(app: MenuBarApp, scenario: String, file: StateFile, out: URL) {
        self.app = app; self.scenario = scenario; self.file = file; self.out = out
        // A click outside closes the drop-down and fails the steps after it, so name its source in the log.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            let pid = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0
            print("OUTSIDE click from pid \(pid) \(NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? "(hardware)")"); fflush(stdout)
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let menu = note.object as? NSMenu else { return }
                self.menuTitles = menu.items.map(\.title)
                // Close the menu from the tracking run loop itself.
                RunLoop.main.perform(inModes: [.eventTracking, .common, .default]) { menu.cancelTracking() }
            }
        }
    }

    // MARK: Reporting
    func check(_ id: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        let text = detail()
        results.append(["id": id, "ok": ok ? "pass" : "FAIL", "detail": text])
        print(ok ? "PASS" : "FAIL", id, text); fflush(stdout)
    }
    func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    var saved: TimerState? { try? file.load() }
    var state: TimerState { app.store.state }
    var button: NSStatusBarButton { app.item.button! }

    // MARK: Events
    func mouse(_ type: NSEvent.EventType, _ window: NSWindow, _ point: NSPoint, _ flags: NSEvent.ModifierFlags = []) {
        let down = type == .leftMouseDown || type == .rightMouseDown
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: down ? 1 : 0)!
        NSApp.postEvent(event, atStart: false)
    }
    func clickItem(right: Bool = false, flags: NSEvent.ModifierFlags = [], settle: Double = 0.4) async {
        let window = button.window!, point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        mouse(right ? .rightMouseDown : .leftMouseDown, window, point, flags)
        mouse(right ? .rightMouseUp : .leftMouseUp, window, point, flags)
        await wait(settle)
    }
    func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], ignoring: String? = nil) {
        guard let panel = app.panel else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: panel.windowNumber, context: nil, characters: characters,
                                         charactersIgnoringModifiers: ignoring ?? characters, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
        }
    }
    func type(_ text: String) async {
        for character in text { key(String(character), code: character == " " ? 49 : 0); await wait(0.03) }
        await wait(0.2)
    }
    func space() async { key(" ", code: 49); await wait(0.3) }
    func escape() async { key("\u{1b}", code: 53); await wait(0.4) }
    func returnKey() async { key("\r", code: 36); await wait(0.3) }
    func endOfLine() async { key("\u{05}", code: 14, flags: .control, ignoring: "e"); await wait(0.15) }

    // MARK: Accessibility tree of the drop-down
    /// SwiftUI's accessibility nodes answer the informal NSAccessibility methods, read here through key-value coding.
    typealias Element = NSObject
    func ax<T>(_ element: Element, _ key: String) -> T? { element.responds(to: NSSelectorFromString(key)) ? element.value(forKey: key) as? T : nil }
    func role(_ element: Element) -> String? { ax(element, "accessibilityRole") }
    func frame(_ element: Element) -> NSRect { (ax(element, "accessibilityFrame") as NSValue?)?.rectValue ?? .zero }
    func elements() -> [Element] {
        guard let root = app.panel?.contentView else { return [] }
        var found: [Element] = []
        func walk(_ element: Any, _ depth: Int) {
            guard depth < 40, let object = element as? Element else { return }
            found.append(object)
            for child in (ax(object, "accessibilityChildren") as [Any]?) ?? [] { walk(child, depth + 1) }
        }
        walk(root, 0)
        return found
    }
    func label(_ element: Element) -> String {
        let parts: [String?] = [ax(element, "accessibilityLabel"), ax(element, "accessibilityTitle"), ax(element, "accessibilityValue")]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ")
    }
    func find(_ text: String, role wanted: NSAccessibility.Role? = nil) -> Element? {
        let all = elements().filter { wanted == nil || role($0) == wanted?.rawValue }
        if let exact = all.first(where: { ax($0, "accessibilityLabel") == text || ax($0, "accessibilityTitle") == text }) { return exact }
        return all.first { ((ax($0, "accessibilityLabel") as String?) ?? "").hasPrefix(text) }
    }
    func texts() -> [String] { elements().filter { role($0) == NSAccessibility.Role.staticText.rawValue }.map(label) }
    /// Clicks an element of the drop-down with posted mouse events at its centre.
    @discardableResult func click(_ text: String, right: Bool = false, settle: Double = 0.45) async -> Bool {
        guard let panel = app.panel, let element = find(text, role: right ? nil : .button) ?? find(text) else { print("  missing element", text); return false }
        let box = frame(element), point = panel.convertPoint(fromScreen: NSPoint(x: box.midX, y: box.midY))
        mouse(right ? .rightMouseDown : .leftMouseDown, panel, point)
        mouse(right ? .rightMouseUp : .leftMouseUp, panel, point)
        await wait(settle)
        return true
    }
    func snapshot(_ name: String) {
        guard let view = app.panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(scenario)-\(name).png"))
    }
    func itemSnapshot(_ name: String) {
        guard let image = button.image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(scenario)-item-\(name).png"))
    }
    var itemWidth: CGFloat { app.item.button?.window?.frame.width ?? 0 }

    // MARK: Scenarios
    func run() async {
        while app.item == nil { await wait(0.01) }
        // Scenarios that never open the drop-down also keep the test item out of the menu bar, so a manager doesn't move it.
        if !opensDropDown { app.item.isVisible = false }
        if opensDropDown || ProcessInfo.processInfo.environment["HARNESS_STOP_ON_INPUT"] != nil { stopOnInput() }
        await wait(0.8)
        switch scenario {
        case "quiet": await quiet()
        case "fresh": await fresh()
        case "restore": await restore()
        case "paused": await paused()
        case "deadline": await deadline()
        case "overdue": await overdue()
        case "damaged": await damaged()
        default: check("scenario", false, "unknown \(scenario)")
        }
        let failures = results.filter { $0["ok"] != "pass" }.count
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted])
        try? data.write(to: out.appendingPathComponent("\(scenario).json"))
        print("SUMMARY \(scenario): \(results.count - failures) passed, \(failures) failed"); fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    /// The drop-down takes the keyboard, so give it back the moment someone touches the Mac. Posted events don't count here.
    func stopOnInput() {
        var last = secondsSinceInput()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let now = secondsSinceInput()
            if now < last { print("STOPPED by mouse or keyboard input"); fflush(stdout); exit(4) }
            last = now
        }
    }

    /// Runs alongside other work: no drop-down, no menu bar item, nothing that takes focus.
    func quiet() async {
        let store = app.store, front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let idle = button.image?.size ?? .zero
        check("Q01 icon: 15 pt semibold timer template at 19 pt", button.image?.isTemplate == true && idle == NSSize(width: 19, height: 19) && button.accessibilityValue() == nil, "\(idle)")
        store.act("start"); await wait(0.3)
        let value = button.accessibilityValue() as? String
        check("Q02 running: time beside the icon, with a ticker", value?.contains(":") == true && (button.image?.size.width ?? 0) > idle.width && app.ticker != nil, "\(String(describing: value))")
        var widths: [CGFloat] = [], values: [String] = []
        for _ in 0..<4 { widths.append(button.image?.size.width ?? 0); values.append(button.accessibilityValue() as? String ?? ""); await wait(1) }
        check("Q03 running: width stays the same each second", Set(widths).count == 1, "\(widths)")
        check("Q04 running: time counts down", Set(values).count >= 3, "\(values)")
        store.act("pause"); await wait(0.2)
        check("Q05 paused: dims and stops ticking", button.appearsDisabled && app.ticker == nil)
        store.act("resume"); await wait(0.2)
        check("Q06 resumed: ticks again", !button.appearsDisabled && app.ticker != nil)
        store.act("end"); await wait(0.2)
        check("Q07 ended: icon only, one ended record saved", button.accessibilityValue() == nil && saved?.history.last?.outcome == .ended && saved?.history.count == 1)
        store.act("stopwatch"); await wait(0.2)
        let stopwatch = button.image?.size ?? .zero
        check("Q08 stopwatch: its icon is the same weight, within 2 pt in size", abs(stopwatch.height - idle.height) <= 2 && button.image?.isTemplate == true, "\(stopwatch)")
        store.act("start"); await wait(1.2)
        check("Q09 stopwatch: counts up", (button.accessibilityValue() as? String).map { $0 != "0:00" } == true, "\(String(describing: button.accessibilityValue()))")
        store.act("reset"); await wait(0.2)
        check("Q10 reset: icon only, nothing more saved", button.accessibilityValue() == nil && saved?.history.count == 1)
        check("Q11 focus: no drop-down or key window, and the frontmost app is someone else", app.panel == nil && NSApp.keyWindow == nil && NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid(), "front \(String(describing: front))")
    }

    func fresh() async {
        // Launch
        check("M01 launch: status item, no Dock icon, no window", app.item != nil && NSApp.activationPolicy() == .accessory && app.panel == nil,
              "policy \(NSApp.activationPolicy().rawValue)")
        check("M02 launch: fixed autosave name and accessibility identifier, empty title",
              app.item.autosaveName == "SimpleTimer" && button.accessibilityIdentifier() == "SimpleTimer" && button.title.isEmpty && button.imagePosition == .imageOnly)
        check("M03 launch: icon only when idle, template image, no ticker", button.image?.isTemplate == true && button.accessibilityValue() == nil && app.ticker == nil,
              "width \(itemWidth)")
        check("M04 launch: nothing saved before the first change", !FileManager.default.fileExists(atPath: file.url.path))
        let idleWidth = itemWidth
        itemSnapshot("idle")

        // Opening and closing from the item
        NSApp.deactivate(); await wait(0.3)
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pointerBefore = NSEvent.mouseLocation.x
        await clickItem()
        check("M05 click: left click opens the drop-down", app.panel?.isVisible == true)
        if let panel = app.panel {
            let frontAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            check("M06 panel: takes the keyboard while the frontmost app stays the same", panel.isKeyWindow && frontAfter == frontBefore && frontAfter != Bundle.main.bundleIdentifier,
                  "front \(frontBefore ?? "-") -> \(frontAfter ?? "-")")
            check("M07 panel: pop-up menu level, all Spaces, full-screen auxiliary",
                  panel.level == .popUpMenu && panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary))
            check("M08 panel: system dialog subrole for tiling window managers", panel.accessibilitySubrole() == .systemDialog, "\(String(describing: panel.accessibilitySubrole()))")
            check("M09 panel: keyboard starts on the view, not a text field", !(panel.firstResponder is NSText))
            let item = button.window!.frame, screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main!
            let bar = MenuBarScreen(screen), shown = bar.shows(item)
            let top = min(shown ? item.minY : screen.frame.maxY - bar.barHeight, screen.frame.maxY - bar.barHeight) - PanelPlacement.gap
            let anchored = shown ? abs(panel.frame.midX - item.midX) < 1 || panel.frame.minX <= screen.visibleFrame.minX + 9 || panel.frame.maxX >= screen.visibleFrame.maxX - 9
                                 // The pointer may have moved since the click, so accept anywhere it has been.
                                 : (min(pointerBefore, NSEvent.mouseLocation.x) - 1...max(pointerBefore, NSEvent.mouseLocation.x) + 1).contains(panel.frame.midX) || panel.frame.minX <= screen.visibleFrame.minX + 9 || panel.frame.maxX >= screen.visibleFrame.maxX - 9
            check("M10 panel: placed \(shown ? "under the visible item" : "under the menu bar at the pointer (item hidden)"), 6 pt below the bar",
                  abs(panel.frame.maxY - top) < 1 && anchored && screen.frame.contains(panel.frame),
                  "item \(item) panel \(panel.frame) screen \(screen.frame) bar \(bar.barHeight)")
            snapshot("open-ready")
        }
        await wait(0.4)
        weak var weakHost = app.panel?.contentView
        await clickItem()
        check("M11 click: left click again closes the drop-down", app.panel == nil)
        await wait(0.3)
        check("M12 close: the drop-down's view is released", weakHost == nil)
        await wait(0.4)
        await clickItem(settle: 0.02)
        await clickItem(settle: 0.4)
        check("M13 click: a second mouse up within 0.3 s is ignored (Thaw)", app.panel != nil)
        await escape()
        await clickItem(flags: .command)
        check("M14 click: ⌘-click (manager drag) is ignored", app.panel == nil)
        await wait(0.4)

        menuTitles = []
        await clickItem(right: true)
        check("M15 right click: menu with Launch at Login and Quit", menuTitles == ["Launch at Login", "", "Quit SimpleTimer"] && app.panel == nil, "\(menuTitles)")
        check("M16 right click: menu is detached afterwards", app.item.menu == nil)
        await wait(0.4)
        menuTitles = []
        await clickItem(flags: .control)
        check("M17 control-click: shows the same menu", menuTitles.contains("Quit SimpleTimer") && app.panel == nil, "\(menuTitles)")
        await wait(1.2)
        // A manager's accessibility press brings no event; the stale right mouse up above must not turn it into a right click.
        menuTitles = []
        _ = button.accessibilityPerformPress()
        await wait(0.4)
        check("M18 accessibility press: opens the drop-down, not the menu", app.panel != nil && menuTitles.isEmpty, "menu \(menuTitles)")
        await wait(0.4)
        _ = button.accessibilityPerformPress()
        await wait(0.4)
        check("M19 accessibility press: a second press closes it", app.panel == nil)
        await wait(0.4)
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        await wait(0.3)
        check("M20 reopen from Finder or Spotlight: shows the drop-down", app.panel != nil)
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        await wait(0.2)
        check("M21 reopen while open: keeps the one drop-down", app.panel != nil)

        // Timer through the keyboard and buttons
        check("M22 alerts: no permission request before Start", Hooks.askedForAlerts == 0)
        await space()
        check("M23 Space: starts the timer and saves it", state.session.phase == .running && saved?.session.phase == .running)
        await wait(0.5)
        check("M24 alerts: permission asked after the first Start", Hooks.askedForAlerts == 1, "asked \(Hooks.askedForAlerts)")
        check("M25 item: shows the time while running, with a ticker", (button.accessibilityValue() as? String)?.contains(":") == true && app.ticker != nil,
              "value \(String(describing: button.accessibilityValue())) width \(itemWidth) idle \(idleWidth)")
        var widths: [CGFloat] = [], values: [String] = []
        for _ in 0..<4 { widths.append(itemWidth); values.append(button.accessibilityValue() as? String ?? ""); await wait(1.0) }
        check("M26 item: width stays the same from second to second", Set(widths).count == 1 && widths[0] > idleWidth, "\(widths) idle \(idleWidth)")
        check("M27 item: time counts down each second", Set(values).count >= 3, "\(values)")
        itemSnapshot("running")
        snapshot("running")
        let clockTexts = texts().filter { $0.contains("Time remaining") }
        check("M28 panel: clock and Ends label", texts().contains { $0.hasPrefix("Ends ") } && !clockTexts.isEmpty, "\(texts())")
        await space()
        check("M29 Space: pauses; item dims and stops ticking", state.session.phase == .paused && button.appearsDisabled && app.ticker == nil)
        check("M30 panel: Paused status and Resume", texts().contains("Paused") && find("Resume", role: .button) != nil, "\(texts())")
        await space()
        check("M31 Space: resumes", state.session.phase == .running && !button.appearsDisabled && app.ticker != nil)
        let history = state.history.count
        let clicked = await click("End")
        check("M32 End button: ends and saves one ended record", clicked && state.session.phase == .ended && state.history.count == history + 1
              && saved?.history.last?.outcome == .ended, "history \(state.history.count) phase \(state.session.phase)")
        check("M33 item: icon only after End", button.accessibilityValue() == nil && app.ticker == nil)
        check("M34 panel: Ended status, Start offered", texts().contains("Ended") && find("Start", role: .button) != nil, "\(texts())")
        await click("Start")
        check("M35 Start button: starts a new attempt", state.session.phase == .running && state.history.count == history + 1)
        let fullDuration = state.session.duration
        await wait(1.2)
        await click("Reset")
        check("M36 Reset button: stops at full duration without saving", state.session.phase == .ready && state.session.remaining == fullDuration
              && state.history.count == history + 1 && saved?.session.phase == .ready)
        await click("Start")
        let running = state.session.id
        await click("Short Break")
        check("M37 switch: picking another type mid-session asks first", texts().contains { $0.hasPrefix("Switch to Short Break") } && state.session.id == running, "\(texts())")
        snapshot("confirm")
        await click("Cancel")
        check("M38 switch: Cancel keeps the running session", state.session.id == running && state.session.phase == .running && state.selected == .work)
        await click("Short Break")
        await click("Switch")
        check("M39 switch: Switch saves it as switched and selects the new type", state.selected == .shortBreak && state.session.phase == .ready
              && state.history.last?.outcome == .switched && saved?.history.count == history + 2, "last \(String(describing: state.history.last?.outcome))")
        await click("Work")
        check("M40 select: picking a type between sessions needs no confirmation", state.selected == .work && state.session.phase == .ready)
        check("M41 footer: shows the time focused today", texts().contains { $0.hasSuffix("focused today") }, "\(texts().filter { $0.contains("focused") })")

        // Duration menu on a session type. A posted right click doesn't pop the menu up, so ask the view for it as AppKit does.
        if let chip = find("Work"), let panel = app.panel, let host = panel.contentView {
            let box = frame(chip), point = panel.convertPoint(fromScreen: NSPoint(x: box.midX, y: box.midY))
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let menu = host.hitTest(host.convert(point, from: nil))?.menu(for: event)
            let titles = menu?.items.map(\.title) ?? []
            check("M42 duration menu: right click on Work lists 15 min to 1 hr 30 min, 45 min ticked",
                  titles == ["15 min", "25 min", "30 min", "45 min", "1 hr", "1 hr 30 min"] && menu?.items[3].state == .on, "\(titles)")
            if let menu, let index = titles.firstIndex(of: "30 min") { menu.performActionForItem(at: index) }
            await wait(0.4)
        }
        check("M43 duration menu: choosing 30 min saves it and resizes the ready session", saved?.presets.first { $0.kind == .work }?.minutes == 30 && state.session.duration == 1800,
              "minutes \(String(describing: saved?.presets.first { $0.kind == .work }?.minutes)) duration \(state.session.duration)")

        // Closing
        await escape()
        check("M44 Esc: closes the drop-down", app.panel == nil)
        await clickItem()
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.makeKeyAndOrderFront(nil)
        await wait(0.4)
        check("M45 focus: another window taking key closes the drop-down", app.panel == nil)
        other.orderOut(nil)
        await wait(0.4)

        // Stopwatch
        await clickItem()
        await click("Switch to stopwatch")
        check("M46 stopwatch: mode button switches to a ready stopwatch", state.session.isUntimed && state.session.phase == .ready && find("Session name") != nil)
        snapshot("stopwatch-ready")
        await escape()
        await clickItem()
        check("M47 stopwatch: reopened drop-down keeps the keyboard off the name field", !(app.panel?.firstResponder is NSText))
        await space()
        check("M48 stopwatch: Space starts it, not a typed space", state.session.phase == .running && state.session.isUntimed && app.store.draft.isEmpty,
              "phase \(state.session.phase) draft '\(app.store.draft)'")
        check("M49 stopwatch: mode button hidden while active", find("Switch to timer") == nil)
        await wait(1.1)
        check("M50 item: stopwatch counts up", (button.accessibilityValue() as? String).map { $0 != "0:00" } == true, "\(String(describing: button.accessibilityValue()))")
        await click("End")
        let stopwatchRecords = state.history.count
        await click("Session name")
        await type("Next")
        await returnKey()
        check("M51 name: a name typed after End is held for the next Start", app.store.draft == "Next" && state.session.phase == .ended, "draft '\(app.store.draft)'")
        await click("Long Break")
        check("M52 name: picking another type after End readies a stopwatch and keeps the name", state.session.phase == .ready && state.session.isUntimed && app.store.draft == "Next")
        await click("Session name")
        check("M53 name: clicking the field starts editing", app.panel?.firstResponder is NSText)
        await endOfLine()
        await type(" chapter")
        check("M54 name: Space inside the field types a space", app.store.draft == "Next chapter" && state.session.phase == .ready, "draft '\(app.store.draft)'")
        await returnKey()
        check("M55 name: Return saves the name on the ready session", saved?.session.title == "Next chapter", "\(String(describing: saved?.session.title))")
        await click("Deep Work")
        check("M56 name: survives a type change", state.session.title == "Next chapter" && app.store.draft == "Next chapter" && state.selected == .deepWork)
        await space()
        check("M57 name: Space after Return starts the named stopwatch", state.session.phase == .running && state.session.title == "Next chapter",
              "phase \(state.session.phase) firstResponder \(String(describing: app.panel?.firstResponder))")
        await click("Session name")
        await endOfLine()
        await type(" two")
        await escape()
        check("M58 rename: closing the drop-down saves the new name", saved?.session.title == "Next chapter two", "\(String(describing: saved?.session.title))")
        await clickItem()
        await click("Session name")
        await endOfLine()
        await type(" three")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        check("M59 quit: a name still being typed is saved on Quit", saved?.session.title == "Next chapter two three", "\(String(describing: saved?.session.title))")
        await escape()
        await clickItem()
        await click("End")
        check("M60 stopwatch: End saves the named record", state.history.count == stopwatchRecords + 1 && state.history.last?.title == "Next chapter two three"
              && state.history.last?.untimed == true, "\(String(describing: state.history.last?.title))")
        check("M61 stopwatch: name clears after End", app.store.draft.isEmpty)
        await click("Switch to timer")
        check("M62 timer: mode button returns to the timer", !state.session.isUntimed && state.session.phase == .ready)

        // Save failure notice
        let directory = file.url.deletingLastPathComponent().path
        chmod(directory, 0o555)
        let before = state
        await space()
        check("M63 save error: action is refused and a notice shows", state == before && texts().contains("Could not save the timer."), "\(texts().suffix(3))")
        chmod(directory, 0o755)
        await space()
        check("M64 save error: the notice clears after the next save", state.session.phase == .running && !texts().contains("Could not save the timer."), "\(texts().suffix(3))")
        await click("Reset")
        await escape()

        // Memory
        weak var lastPanel: DropPanel?
        for _ in 0..<10 { await clickItem(); lastPanel = app.panel; await escape() }
        await wait(0.5)
        check("M65 memory: ten open and close cycles leave no drop-down alive", lastPanel == nil && app.panel == nil)
    }

    func restore() async {
        check("M66 restore: running named stopwatch comes back running", state.session.phase == .running && state.session.title == "Chapter three" && app.store.draft == "Chapter three")
        let value = button.accessibilityValue() as? String ?? ""
        check("M67 restore: item shows the elapsed time and ticks", value.hasPrefix("2:0") && app.ticker != nil, "value \(value) width \(itemWidth)")
        itemSnapshot("restore")
        await clickItem()
        check("M68 restore: drop-down shows the name and Started label", texts().contains { $0.hasPrefix("Started ") } && (find("Session name").flatMap { ax($0, "accessibilityValue") as String? }) == "Chapter three",
              "\(texts()) field \(String(describing: find("Session name").flatMap { ax($0, "accessibilityValue") as String? }))")
        snapshot("restore")
    }

    func paused() async {
        check("M69 paused relaunch: stays paused, dimmed, no ticker", state.session.phase == .paused && button.appearsDisabled && app.ticker == nil,
              "value \(String(describing: button.accessibilityValue()))")
        let value = button.accessibilityValue() as? String
        await wait(1.5)
        check("M70 paused relaunch: time does not move", button.accessibilityValue() as? String == value && value != nil, "\(String(describing: value))")
    }

    func deadline() async {
        check("M71 deadline: running timer counts down after launch", state.session.phase == .running && app.ticker != nil)
        await wait(4.5)
        check("M72 deadline: completes at zero and saves one completed record", state.session.phase == .completed && state.history.count == 1
              && saved?.history.first?.outcome == .completed, "phase \(state.session.phase) history \(state.history.count)")
        check("M73 deadline: item returns to the icon and stops ticking", button.accessibilityValue() == nil && app.ticker == nil)
        await clickItem()
        check("M74 deadline: drop-down shows Complete with Start", texts().contains("Complete") && find("Start", role: .button) != nil, "\(texts())")
    }

    func overdue() async {
        check("M75 overdue: a timer that finished while quit completes on launch, saved once",
              state.session.phase == .completed && saved?.history.filter { $0.outcome == .completed }.count == 1, "history \(String(describing: saved?.history.map(\.outcome)))")
    }

    func damaged() async {
        let bytes = try? Data(contentsOf: file.url)
        await clickItem()
        check("M76 damaged save: notice shows instead of history", texts().contains("Saved data could not be read."), "\(texts())")
        await space()
        check("M77 damaged save: Start is refused and the file is untouched", state.session.phase == .ready && (try? Data(contentsOf: file.url)) == bytes)
    }
}

// MARK: Launch
func secondsSinceInput() -> Double { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!) }
let scenario = ProcessInfo.processInfo.environment["HARNESS_SCENARIO"] ?? "fresh"
let opensDropDown = !["quiet", "paused", "overdue"].contains(scenario)
if opensDropDown {
    // Never take the keyboard from someone using the Mac.
    let idle = Double(ProcessInfo.processInfo.environment["HARNESS_IDLE"] ?? "") ?? 60
    if secondsSinceInput() < idle { print("WAITING for \(Int(idle)) seconds without mouse or keyboard input"); fflush(stdout) }
    while secondsSinceInput() < idle { sleep(2) }
}
let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
guard !home.isEmpty, support.resolvingSymlinksInPath().path.hasPrefix(URL(fileURLWithPath: home).resolvingSymlinksInPath().path) else { print("refusing: Application Support is not inside the test home (\(support.path))"); exit(2) }
let stateFile = StateFile(url: support.appendingPathComponent("SimpleTimer/state.json"))
try? FileManager.default.createDirectory(at: stateFile.url.deletingLastPathComponent(), withIntermediateDirectories: true)
let now = Date()
if ProcessInfo.processInfo.environment["HARNESS_KEEP"] == nil {
    var seed = TimerState()
    switch scenario {
    case "restore": seed.perform("stopwatch", at: now - 200); seed.perform("start", title: "Chapter three", at: now - 125)
    case "paused": seed.perform("start", at: now - 300); seed.perform("pause", at: now - 60)
    case "deadline": seed.perform("start", at: now - (45 * 60 - 3))
    case "overdue": seed.perform("start", at: now - 46 * 60)
    default: break
    }
    if scenario == "damaged" { try! Data("{ not json".utf8).write(to: stateFile.url) }
    else if scenario != "fresh" { try! stateFile.save(seed) }
}
let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HARNESS_OUT"] ?? NSTemporaryDirectory())
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = MenuBarApp()
    application.delegate = delegate
    let harness = Harness(app: delegate, scenario: scenario, file: stateFile, out: out)
    DispatchQueue.main.async { Task { @MainActor in await harness.run() } }
    DispatchQueue.main.asyncAfter(deadline: .now() + 240) { print("TIMEOUT"); exit(3) }
    application.run()
}
