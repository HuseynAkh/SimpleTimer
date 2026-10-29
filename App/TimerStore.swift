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
    func save() { guard storageAvailable else { return }; do { try file.save(state); PhoneConnection.shared.publish(state) } catch { notice = "Could not save the timer: \(error.localizedDescription)" } }
    func refresh() async { guard storageAvailable, !busy else { return }; busy = true; defer { busy = false }; state.reconcile(at: Date()); save(); await sync(); await reconcileActivities() }
    func perform(_ action: String, kind: SessionKind? = nil) async {
        guard storageAvailable, !busy else { return }; busy = true; defer { busy = false }
        state.reconcile(at: Date())
        switch action {
        case "start": state.start(at: Date())
        case "restart": state.reset(confirmed: true); state.start(at: Date())
        case "pause": state.pause(at: Date())
        case "resume": state.resume(at: Date())
        case "end": state.end(at: Date())
        case "reset": state.reset(confirmed: true)
        case "select": if let kind { state.select(kind, confirmed: true) }
        default: return
        }
        save()
        if action == "start" || action == "restart" {
            let settings = await notifications.notificationSettings()
            if settings.authorizationStatus == .notDetermined { _ = try? await notifications.requestAuthorization(options: [.alert, .sound]) }
        }
        state.reconcile(at: Date())
        save()
        await sync(create: action == "start" || action == "restart")
    }
    func edit(_ preset: Preset) { state.edit(preset); save() }
    func restore() { state.restoreDefaults(); save() }
    func sync(create: Bool = false) async {
        notifications.removePendingNotificationRequests(withIdentifiers: ["completion"])
        notifications.removeDeliveredNotifications(withIdentifiers: ["completion"])
        let s = state.session
        if s.phase == .running, let end = s.end, end > Date() {
            let content = UNMutableNotificationContent(); content.title = "\(s.preset.name) finished"; content.body = "Take a moment. Your next session is up to you."; if state.sound { content.sound = .default }
            let request = UNNotificationRequest(identifier: "completion", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false))
            do { try await notifications.add(request) } catch { notice = "Completion alerts are unavailable. Your timer still works." }
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
    private func reconcileActivities() async {
        // Never recreate an activity the user dismissed; only an explicit Start creates one.
        for activity in Activity<TimerAttributes>.activities where activity.attributes.sessionID != state.session.id || state.session.phase == .ready || state.session.phase == .ended {
            let s = state.session
            await activity.end(ActivityContent(state: TimerAttributes.ContentState(phase: s.phase.rawValue, end: nil, remaining: s.remaining, duration: s.duration), staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
