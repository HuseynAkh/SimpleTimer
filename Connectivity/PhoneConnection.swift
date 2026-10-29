import Foundation
import WatchConnectivity

@MainActor final class PhoneConnection: NSObject, WCSessionDelegate {
    static let shared = PhoneConnection()
    private var lastAcknowledgedCommand: UUID?
    private let preferences = UserDefaults.standard

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @discardableResult func publish(_ state: TimerState) -> Data? {
        let revision = preferences.integer(forKey: "watchSnapshotRevision") + 1
        preferences.set(revision, forKey: "watchSnapshotRevision")
        let snapshot = WatchSnapshot(state: state, revision: Int64(revision), acknowledgedCommandID: lastAcknowledgedCommand)
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return data }
        // Latest-state delivery survives disconnection. A foreground push avoids
        // waiting for the system's background application-context delivery budget.
        try? session.updateApplicationContext(["snapshot": data])
        if session.isReachable { session.sendMessage(["snapshot": data], replyHandler: nil, errorHandler: { _ in }) }
        return data
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(TimerStore.shared.state) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.publish(TimerStore.shared.state) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.publish(TimerStore.shared.state) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let commandData = message["command"] as? Data
        Task { @MainActor in
            let store = TimerStore.shared
            var error: String?
            if !store.storageAvailable {
                error = "Open SimpleTimer on iPhone to recover its saved data."
            } else if let commandData {
                if let command = try? JSONDecoder().decode(WatchCommand.self, from: commandData) {
                    if let id = command.id, id == self.lastAcknowledgedCommand {
                        // Repeated delivery acknowledges the original command, never applies it twice.
                    } else if !command.isValid(for: store.state) {
                        error = "The iPhone timer changed. Your Watch is up to date now."
                    } else if store.apply(command.action, kind: command.kind, publish: false) {
                        self.lastAcknowledgedCommand = command.id
                    } else { error = "The timer could not be saved on iPhone." }
                } else { error = "Update SimpleTimer on both devices to reconnect." }
            } else { store.refreshImmediately(publish: false) }
            var reply: [String: Any] = [:]
            if let data = self.publish(store.state) { reply["snapshot"] = data }
            if let error { reply["error"] = error }
            // Nothing in this path awaits ActivityKit, notification permissions or alerts.
            replyHandler(reply)
        }
    }
}
