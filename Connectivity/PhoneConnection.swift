import Foundation
import WatchConnectivity

@MainActor final class PhoneConnection: NSObject, WCSessionDelegate {
    static let shared = PhoneConnection()
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func publish(_ state: TimerState) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(WatchSnapshot(state: state)) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(TimerStore.shared.state) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.publish(TimerStore.shared.state) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let commandData = message["command"] as? Data
        Task { @MainActor in
            let store = TimerStore.shared
            guard store.storageAvailable, !store.busy else { replyHandler(["error": "Open SimpleTimer on iPhone and try again."]); return }
            if let commandData {
                guard let command = try? JSONDecoder().decode(WatchCommand.self, from: commandData), command.isValid(for: store.state) else {
                    replyHandler(["error": "Timer changed. Refresh and try again."]); return
                }
                await store.perform(command.action, kind: command.kind)
            } else { await store.refresh() }
            if let data = try? JSONEncoder().encode(WatchSnapshot(state: store.state)) { replyHandler(["snapshot": data]) }
            else { replyHandler(["error": "Could not read timer."]) }
        }
    }
}
