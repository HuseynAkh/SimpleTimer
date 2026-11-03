import Foundation
import WatchConnectivity

/// The Watch keeps its own copy of the timer, applies every tap at once and syncs with the iPhone
/// whenever WatchConnectivity can deliver. It never waits for the phone before showing a change.
@MainActor final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var state: TimerState
    @Published private(set) var reachable = false
    @Published private(set) var unsynced: Bool
    private let defaults = UserDefaults.standard
    /// The newest change the phone has replied to. Sending stops repeating only after a reply.
    private var deliveredChange: Date?
    private var awaitingReply: UUID?

    var session: Session { state.session }

    override init() {
        state = Self.restore(UserDefaults.standard)
        unsynced = UserDefaults.standard.bool(forKey: "unsynced")
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func perform(_ action: String, kind: SessionKind? = nil, title: String? = nil) {
        guard state.perform(action, kind: kind, title: title, at: Date()) else { return }
        unsynced = true
        persist(); push()
    }

    /// Runs when the app becomes active and when a timer reaches zero.
    func refresh() {
        let before = state
        state.reconcile(at: Date())
        if let data = WCSession.default.receivedApplicationContext["sync"] as? Data { receive(data) }
        if state != before { unsynced = true; persist() }
        // Sending this copy also asks the phone for its latest one in the reply.
        push()
    }

    private func push() {
        let session = WCSession.default
        guard session.activationState == .activated, let data = try? JSONEncoder().encode(state.envelope(from: .watch)) else { return }
        let sent = state.changedAt; reachable = session.isReachable
        // Delivered later if the phone is away; a direct message reaches it now when it is reachable.
        try? session.updateApplicationContext(["sync": data])
        guard reachable else { return }
        let id = UUID(); awaitingReply = id
        session.sendMessage(["sync": data], replyHandler: { reply in
            let data = reply["sync"] as? Data
            Task { @MainActor in
                self.awaitingReply = nil; self.reachable = true; self.deliveredChange = sent
                if let data { self.receive(data) }
            }
        }, errorHandler: { _ in
            // Reachability can lag; a failed send is the clearer signal that the phone is away.
            Task { @MainActor in self.reachable = false }
        })
        // A reply that never comes means the same. The change is already saved here and in the context.
        Task {
            try? await Task.sleep(for: .seconds(5))
            if awaitingReply == id { reachable = false }
        }
    }

    private func receive(_ data: Data) {
        guard let remote = try? JSONDecoder().decode(SyncEnvelope.self, from: data), remote.origin == .phone else { return }
        let before = state, wasUnsynced = unsynced
        state.merge(remote, at: Date())
        let acknowledged = Set(remote.finishedIDs)
        state.history.removeAll { acknowledged.contains($0.id) }
        state.history = Array(state.history.suffix(100))
        unsynced = remote.session != state.session || !state.history.isEmpty
        if state != before || unsynced != wasUnsynced { persist() }
        // Anything the phone has not replied to yet goes again, including a session saved by this merge.
        if unsynced && state.changedAt != deliveredChange { push() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "state") }
        defaults.set(unsynced, forKey: "unsynced")
    }

    private static func restore(_ defaults: UserDefaults) -> TimerState {
        if let data = defaults.data(forKey: "state"), let state = try? JSONDecoder().decode(TimerState.self, from: data) { return state }
        // Earlier builds cached only the phone's last snapshot; it seeds this copy without outranking the phone.
        var state = TimerState()
        if let data = defaults.data(forKey: "snapshot"), let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            state.presets = snapshot.presets; state.session = snapshot.session; state.selected = snapshot.session.preset.kind
        }
        return state
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable; self.refresh() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            if reachable { self.push() }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["sync"] as? Data
        Task { @MainActor in if let data { self.receive(data) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["sync"] as? Data
        Task { @MainActor in if let data { self.receive(data) } }
    }
}
