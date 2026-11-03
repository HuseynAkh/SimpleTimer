import Foundation
import UserNotifications

/// The Mac keeps its own timer and history beside the iPhone's; the two never sync.
@MainActor final class MacStore: ObservableObject {
    @Published private(set) var state: TimerState
    /// Advanced by the menu bar ticker only while a session runs, so idle and paused panels never redraw.
    @Published private(set) var now: Date
    /// The stopwatch name being typed. It survives closing the panel and is saved like the iPhone's.
    @Published var draft = ""
    @Published private(set) var notice: String?
    var changed: (() -> Void)?
    private let file: StateFile?
    private var writable = true
    private var askForAlerts = false
    private lazy var alerts = LatestEffectsQueue<Session> { [weak self] session in await self?.updateAlert(session) }

    init(file: StateFile?, state: TimerState = TimerState(), now: Date = Date()) {
        self.file = file; self.state = state; self.now = now
        if let file {
            do { self.state = try file.load() } catch {
                // Never replace unreadable history with an empty save.
                let manager = FileManager.default
                if manager.fileExists(atPath: file.url.path) || manager.fileExists(atPath: file.backupURL.path) {
                    writable = false; notice = "Saved data could not be read."
                }
            }
        }
        self.state.reconcile(at: now); syncDraft()
    }
    static func standard() -> MacStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MacStore(file: StateFile(url: directory.appendingPathComponent("SimpleTimer/state.json")))
    }

    /// Panel actions keep a name being typed. A mode switch starts a fresh, unnamed session.
    func act(_ action: String, kind: SessionKind? = nil) {
        switch action {
        case "timer", "stopwatch": draft = ""; perform(action)
        case "start": perform(action, title: state.session.isUntimed ? draft : nil)
        default: commitDraft(); perform(action, kind: kind)
        }
    }
    @discardableResult func perform(_ action: String, kind: SessionKind? = nil, title: String? = nil) -> Bool {
        let previous = state; now = Date()
        guard writable, state.perform(action, kind: kind, title: title, at: now), save() else { state = previous; return false }
        if action == "start" { askForAlerts = true }
        syncDraft(); didChange()
        return true
    }
    func commitDraft() {
        let session = state.session
        guard session.isUntimed, session.isActive || session.phase == .ready, TimerState.normalizedTitle(draft) != session.title else { return }
        perform("title", title: draft)
    }
    func setMinutes(_ minutes: Int, for kind: SessionKind) {
        guard writable, var preset = state.presets.first(where: { $0.kind == kind }), preset.minutes != minutes else { return }
        let previous = state; preset.minutes = minutes; state.edit(preset)
        guard save() else { state = previous; return }
        didChange()
    }
    func tick() {
        now = Date()
        if state.session.phase == .running && state.session.remaining(at: now) <= 0 { refresh() }
    }
    /// Completes an overdue session, for example after sleep or relaunch.
    func refresh() {
        let previous = state; now = Date(); state.reconcile(at: now)
        if state != previous { if writable { _ = save() }; syncDraft() }
        didChange()
    }
    private func save() -> Bool {
        guard let file else { return true }
        do { try file.save(state); notice = nil; return true } catch { notice = "Could not save the timer."; return false }
    }
    private func didChange() { changed?(); if file != nil { alerts.submit(state.session) } }
    private func syncDraft() {
        let session = state.session
        if session.phase == .ended || session.phase == .completed { draft = "" }
        else if let title = session.title { draft = title }
        else if session.isActive { draft = "" }
    }
    /// Only timed sessions announce a finish. Permission is asked after an explicit Start, never at launch.
    private func updateAlert(_ session: Session) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["completion"])
        if session.phase != .completed { center.removeDeliveredNotifications(withIdentifiers: ["completion"]) }
        guard session.phase == .running, !session.isUntimed, let end = session.end, end > Date() else { return }
        if askForAlerts, await center.notificationSettings().authorizationStatus == .notDetermined {
            askForAlerts = false
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional, state.session == session else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(session.preset.name) finished"; content.body = "Take a moment. Your next session is up to you."
        if state.sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "completion", content: content, trigger: trigger))
    }
}
