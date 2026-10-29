import Foundation
import WatchConnectivity

@MainActor final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private var sync = WatchSyncState()
    @Published private(set) var refreshing = false
    @Published private(set) var message: String?
    private var refreshID: UUID?
    private var timeout: Task<Void, Never>?
    private let cache = UserDefaults.standard

    var snapshot: WatchSnapshot? { sync.snapshot }
    var displayedSession: Session? { sync.displayedSession }
    var busy: Bool { sync.pending != nil }

    override init() {
        super.init()
        if let data = cache.data(forKey: "snapshot"), let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            sync = WatchSyncState(snapshot: value)
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh(manual: Bool = false) {
        if let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data { accept(data) }
        guard refreshID == nil else { return }
        guard connected else {
            if manual || snapshot == nil { message = "Connect to your iPhone to update the timer." }
            return
        }
        let id = UUID(); refreshID = id; refreshing = true
        WCSession.default.sendMessage(["refresh": true], replyHandler: { reply in
            let data = reply["snapshot"] as? Data
            Task { @MainActor in
                if self.refreshID == id { self.refreshID = nil; self.refreshing = false }
                if let data { self.accept(data) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in self.finishRefresh(id, manual: manual) }
        })
        Task {
            try? await Task.sleep(for: .seconds(8))
            finishRefresh(id, manual: manual)
        }
    }

    func perform(_ action: String, kind: SessionKind? = nil) {
        guard connected else { message = "Connect to your iPhone to change the timer."; return }
        message = nil
        let command: WatchCommand?
        if action == "select", let kind { command = sync.select(kind, at: Date()) }
        else { command = sync.begin(action, at: Date()) }
        if let command { send(command) }
        else if action != "select" && busy { message = "Updating your session…" }
    }

    private var connected: Bool {
        WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    private func send(_ command: WatchCommand) {
        guard let id = command.id, let data = try? JSONEncoder().encode(command) else { return }
        guard connected else { fail(id); return }
        timeout?.cancel()
        WCSession.default.sendMessage(["command": data], replyHandler: { reply in
            let data = reply["snapshot"] as? Data, error = reply["error"] as? String
            Task { @MainActor in
                if let error {
                    let relevant = self.sync.fail(id)
                    if let data { self.accept(data) }
                    if relevant { self.message = error }
                } else if let data, let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
                    self.sync.reply(to: id, snapshot: value)
                    self.didReceiveState()
                } else { self.fail(id) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in self.fail(id) }
        })
        timeout = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            fail(id)
        }
    }

    private func fail(_ id: UUID) {
        guard sync.fail(id) else { return } // Ignore errors arriving after a push receipt.
        timeout?.cancel()
        message = "Couldn’t confirm the change. Reconnecting to iPhone…"
        refresh() // Read-only recovery. Never replay an uncertain timer command.
    }

    private func finishRefresh(_ id: UUID, manual: Bool) {
        guard refreshID == id else { return }
        refreshID = nil; refreshing = false
        if manual || snapshot == nil {
            message = snapshot == nil ? "Connect to your iPhone to load the timer." : "iPhone is unavailable. Your last timer is shown."
        }
    }

    private func accept(_ data: Data) {
        guard let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        guard sync.receive(value) else { return }
        didReceiveState()
    }

    private func didReceiveState() {
        message = nil
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { cache.set(data, forKey: "snapshot") }
        if sync.pending == nil {
            timeout?.cancel()
            if let next = sync.nextSelection(at: Date()) { send(next) }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        Task { @MainActor in if let data { self.accept(data) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["snapshot"] as? Data
        Task { @MainActor in if let data { self.accept(data) } }
    }
}
