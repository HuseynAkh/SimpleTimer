import Foundation

/// Transport-independent watch state. Only confirmed phone state is cached.
public struct WatchSyncState: Sendable {
    public private(set) var snapshot: WatchSnapshot?
    public private(set) var pending: WatchCommand?
    public private(set) var desiredSelection: SessionKind?

    public init(snapshot: WatchSnapshot? = nil) { self.snapshot = snapshot }

    public var displayedSession: Session? {
        guard let snapshot else { return nil }
        if let kind = desiredSelection, kind != snapshot.session.preset.kind,
           let preset = snapshot.presets.first(where: { $0.kind == kind }) {
            return Session(preset: preset)
        }
        return snapshot.session
    }

    public mutating func select(_ kind: SessionKind, at now: Date) -> WatchCommand? {
        guard snapshot?.presets.contains(where: { $0.kind == kind }) == true else { return nil }
        // A newer selection replaces an unsent selection, never an in-flight timer action.
        guard pending == nil || pending?.action == "select" else { return nil }
        desiredSelection = kind
        return nextSelection(at: now)
    }

    public mutating func nextSelection(at now: Date) -> WatchCommand? {
        guard pending == nil, let snapshot, let kind = desiredSelection else { return nil }
        guard kind != snapshot.session.preset.kind else { desiredSelection = nil; return nil }
        let command = WatchCommand(action: "select", sessionID: snapshot.session.id, kind: kind, expiresAt: now.addingTimeInterval(8))
        pending = command
        return command
    }

    public mutating func begin(_ action: String, at now: Date) -> WatchCommand? {
        guard pending == nil, desiredSelection == nil, let snapshot else { return nil }
        let command = WatchCommand(action: action, sessionID: snapshot.session.id, expiresAt: now.addingTimeInterval(8))
        pending = command
        return command
    }

    @discardableResult public mutating func receive(_ value: WatchSnapshot) -> Bool {
        let newer = snapshot.map { value.isNewer(than: $0) } ?? true
        if newer { snapshot = value }
        // A push/context receipt is sufficient even if the direct reply is lost.
        let acknowledged = pending?.id != nil && value.acknowledgedCommandID == pending?.id
        if acknowledged { pending = nil }
        finishSelectionIfConfirmed()
        return newer || acknowledged
    }

    public mutating func reply(to id: UUID, snapshot value: WatchSnapshot) {
        receive(value)
        // Older phones don't include receipts. Their direct reply still confirms delivery.
        if pending?.id == id { pending = nil }
        finishSelectionIfConfirmed()
    }

    @discardableResult public mutating func fail(_ id: UUID) -> Bool {
        guard pending?.id == id else { return false }
        pending = nil; desiredSelection = nil
        return true
    }

    private mutating func finishSelectionIfConfirmed() {
        if pending == nil, desiredSelection == snapshot?.session.preset.kind { desiredSelection = nil }
    }
}
