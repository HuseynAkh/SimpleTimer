import Foundation
import WatchConnectivity

@MainActor final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WatchSnapshot?
    @Published var busy = false
    @Published var message: String?
    private var requestID: UUID?
    private let cache = UserDefaults.standard
    override init() {
        super.init()
        if let data = cache.data(forKey: "snapshot") { snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func refresh() { send(nil) }
    func perform(_ action: String, kind: SessionKind? = nil) {
        guard let snapshot else { return }
        send(WatchCommand(action: action, sessionID: snapshot.session.id, kind: kind))
    }
    private func send(_ command: WatchCommand?) {
        guard !busy else { return }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            message = "Open SimpleTimer on your nearby iPhone to connect."; return
        }
        busy = true; message = nil
        let id = UUID(); requestID = id
        var payload: [String: Any] = ["refresh": true]
        if let command, let data = try? JSONEncoder().encode(command) { payload = ["command": data] }
        WCSession.default.sendMessage(payload, replyHandler: { reply in
            let data = reply["snapshot"] as? Data, error = reply["error"] as? String
            Task { @MainActor in
                guard self.requestID == id else { return }
                self.busy = false; self.message = error
                if let data { self.accept(data) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.requestID == id else { return }
                self.busy = false; self.message = "Connection lost. Refresh to check the timer before trying again."
            }
        })
        Task {
            try? await Task.sleep(for: .seconds(12))
            if requestID == id && busy { busy = false; requestID = nil; message = "No reply. Refresh to check the timer." }
        }
    }
    private func accept(_ data: Data) {
        guard let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data), value.updatedAt >= (snapshot?.updatedAt ?? .distantPast) else { return }
        snapshot = value; cache.set(data, forKey: "snapshot")
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["snapshot"] as? Data
        Task { @MainActor in if let data { self.accept(data) }; self.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        Task { @MainActor in if let data { self.accept(data) } }
    }
}
