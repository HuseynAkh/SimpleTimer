import Foundation
import WatchConnectivity

/// Both devices keep a full copy of the current session and change it at once. The phone merges what
/// the Watch sends and replies with its merged copy; application context carries the latest state
/// across disconnections in both directions.
@MainActor final class PhoneConnection: NSObject, WCSessionDelegate {
    static let shared = PhoneConnection()
    private var lastAcknowledgedCommand: UUID?
    private let preferences = UserDefaults.standard

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @discardableResult func publish(_ state: TimerState, push: Bool = true) -> [String: Any] {
        // Unreadable saved data leaves a blank placeholder in memory; never let the Watch adopt it.
        guard TimerStore.shared.storageAvailable else { return [:] }
        let revision = preferences.integer(forKey: "watchSnapshotRevision") + 1
        preferences.set(revision, forKey: "watchSnapshotRevision")
        var payload: [String: Any] = [:]
        // Older Watch builds read "snapshot" while both apps update; current builds read "sync".
        if let data = try? JSONEncoder().encode(WatchSnapshot(state: state, revision: Int64(revision), acknowledgedCommandID: lastAcknowledgedCommand)) { payload["snapshot"] = data }
        if let data = try? JSONEncoder().encode(state.envelope(from: .phone)) { payload["sync"] = data }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return payload }
        try? session.updateApplicationContext(payload)
        if push && session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in }) }
        return payload
    }

    @discardableResult private func merge(_ data: Data?) -> Bool {
        guard let data, let remote = try? JSONDecoder().decode(SyncEnvelope.self, from: data), remote.origin == .watch else { return false }
        return TimerStore.shared.merge(remote)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Pick up anything the Watch changed while this app was not running.
        let pending = session.receivedApplicationContext["sync"] as? Data
        Task { @MainActor in self.merge(pending); self.publish(TimerStore.shared.state) }
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
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["sync"] as? Data
        Task { @MainActor in if self.merge(data) { self.publish(TimerStore.shared.state) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["sync"] as? Data
        Task { @MainActor in if self.merge(data) { self.publish(TimerStore.shared.state) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let sync = message["sync"] as? Data, commandData = message["command"] as? Data
        Task { @MainActor in
            let store = TimerStore.shared
            var error: String?
            if !store.storageAvailable {
                error = "Open SimpleTimer on iPhone to recover its saved data."
            } else if sync != nil {
                self.merge(sync)
            } else if let commandData {
                // Commands come only from older Watch builds during an update.
                if let command = try? JSONDecoder().decode(WatchCommand.self, from: commandData) {
                    if let id = command.id, id == self.lastAcknowledgedCommand {
                        // Repeated delivery acknowledges the original command, never applies it twice.
                    } else if !command.isValid(for: store.state) {
                        error = "The iPhone timer changed. Your Watch is up to date now."
                    } else if store.apply(command.action, kind: command.kind, title: command.title, publish: false) {
                        self.lastAcknowledgedCommand = command.id
                    } else { error = "The timer could not be saved on iPhone." }
                } else { error = "Update SimpleTimer on both devices to reconnect." }
            } else { store.refreshImmediately(publish: false) }
            var reply = self.publish(store.state, push: false)
            if let error { reply["error"] = error }
            // Nothing in this path awaits ActivityKit, notification permissions or alerts.
            replyHandler(reply)
        }
    }
}
