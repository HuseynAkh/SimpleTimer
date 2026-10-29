import SwiftUI
import ActivityKit
import UserNotifications

@MainActor final class TimerStore: ObservableObject {
    static let shared = TimerStore()
    @Published var state: TimerState
    @Published var notice: String?
    @Published var busy = false
    @Published private(set) var storageAvailable = true
    private let file: StateFile
    private let notifications = UNUserNotificationCenter.current()
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = StateFile(url: directory.appendingPathComponent("SimpleTimer/state.json"))
        do { state = try file.load() } catch { state = TimerState(); if FileManager.default.fileExists(atPath: file.url.path) || FileManager.default.fileExists(atPath: file.backupURL.path) { storageAvailable = false; notice = "Saved data could not be read. It has been kept unchanged for recovery." } }
        state.reconcile(at: Date())
    }
    private var activityToCreate: UUID?
    private var requestingPermission = false
    private lazy var effects = LatestEffectsQueue<TimerState> { [weak self] state in
        guard let self else { return }
        let create = self.activityToCreate == state.session.id
        if create { self.activityToCreate = nil }
        await self.applySystemEffects(state, create: create)
    }

    @discardableResult func save(publish: Bool = true) -> Bool {
        guard storageAvailable else { return false }
        do {
            try file.save(state)
            if publish { PhoneConnection.shared.publish(state) }
            return true
        }
        catch { notice = "Could not save the timer: \(error.localizedDescription)"; return false }
    }

    func refresh() async { refreshImmediately() }

    func refreshImmediately(publish: Bool = true) {
        guard storageAvailable else { return }
        state.reconcile(at: Date())
        save(publish: publish); effects.submit(state)
    }

    /// No suspension between validation, mutation and durable save. Watch replies
    /// can acknowledge this commit without waiting for notifications or ActivityKit.
    @discardableResult func apply(_ action: String, kind: SessionKind? = nil, publish: Bool = true) -> Bool {
        guard storageAvailable, !busy else { return false }
        busy = true; defer { busy = false }
        let previous = state, now = Date()
        guard state.perform(action, kind: kind, at: now) else { state = previous; return false }
        guard save(publish: publish) else { state = previous; return false }
        if action == "start" { activityToCreate = state.session.id }
        if action == "reset" || action == "restart" {
            activityToCreate = nil
            notifications.removePendingNotificationRequests(withIdentifiers: ["completion"])
            notifications.removeDeliveredNotifications(withIdentifiers: ["completion"])
        }
        effects.submit(state)
        return true
    }

    func perform(_ action: String, kind: SessionKind? = nil) async {
        guard apply(action, kind: kind) else { return }
        // Permission UI belongs to an explicit iPhone action, never a Watch reply.
        if action == "start" && !requestingPermission {
            requestingPermission = true
            Task {
                defer { requestingPermission = false }
                let settings = await notifications.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
                    effects.submit(state)
                }
            }
        }
    }
    func edit(_ preset: Preset) { state.edit(preset); save() }
    func restore() { state.restoreDefaults(); save() }
    func sync() async { effects.submit(state) }

    private func applySystemEffects(_ state: TimerState, create: Bool) async {
        notifications.removePendingNotificationRequests(withIdentifiers: ["completion"])
        notifications.removeDeliveredNotifications(withIdentifiers: ["completion"])
        let s = state.session
        let authorization = await notifications.notificationSettings().authorizationStatus
        guard self.state.session == s else { return }
        if s.phase == .running, let end = s.end, end > Date(),
           authorization == .authorized || authorization == .provisional || authorization == .ephemeral {
            let content = UNMutableNotificationContent(); content.title = "\(s.preset.name) finished"; content.body = "Take a moment. Your next session is up to you."; if state.sound { content.sound = .default }
            let request = UNNotificationRequest(identifier: "completion", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false))
            do { try await notifications.add(request) } catch { notice = "Completion alerts are unavailable. Your timer still works." }
            if self.state.session != s {
                notifications.removePendingNotificationRequests(withIdentifiers: ["completion"])
                return
            }
        }
        let value = TimerAttributes.ContentState(phase: s.phase.rawValue, end: s.end, remaining: s.remaining, duration: s.duration)
        let content = ActivityContent(state: value, staleDate: s.end)
        var found = false
        for activity in Activity<TimerAttributes>.activities {
            if activity.attributes.sessionID == s.id && s.isActive {
                found = true; await activity.update(content)
            } else {
                await activity.end(content, dismissalPolicy: s.phase == .completed ? .after(Date().addingTimeInterval(300)) : .immediate)
            }
        }
        if create && !found && s.isActive && ActivityAuthorizationInfo().areActivitiesEnabled {
            do { _ = try Activity.request(attributes: TimerAttributes(sessionID: s.id, name: s.preset.name, symbol: s.preset.kind.symbol, color: s.preset.color), content: content, pushType: nil) }
            catch { notice = "Live Activity unavailable. Your timer and completion alert are independent of it." }
        }
    }
}
