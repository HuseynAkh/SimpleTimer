import Foundation

/// The phone owns the timer. The watch gets a small read-only snapshot, never history.
public struct WatchSnapshot: Codable, Sendable {
    public let session: Session
    public let presets: [Preset]
    public let updatedAt: Date
    public let revision: Int64?
    public let acknowledgedCommandID: UUID?
    public init(state: TimerState, at date: Date = Date(), revision: Int64? = nil, acknowledgedCommandID: UUID? = nil) {
        session = state.session; presets = state.presets; updatedAt = date
        self.revision = revision; self.acknowledgedCommandID = acknowledgedCommandID
    }

    public func isNewer(than other: WatchSnapshot) -> Bool {
        if let revision, let previous = other.revision { return revision > previous }
        if other.revision != nil && revision == nil { return false }
        return updatedAt >= other.updatedAt
    }
}
public struct WatchCommand: Codable, Sendable {
    // Optional fields keep installed older companions compatible during an update.
    public let id: UUID?
    public let expiresAt: Date?
    public let action: String
    public let sessionID: UUID
    public let kind: SessionKind?
    public init(action: String, sessionID: UUID, kind: SessionKind? = nil, id: UUID = UUID(), expiresAt: Date? = nil) {
        self.action = action; self.sessionID = sessionID; self.kind = kind; self.id = id; self.expiresAt = expiresAt
    }
    public func isValid(for state: TimerState, at now: Date = Date()) -> Bool {
        if let expiresAt, expiresAt <= now { return false }
        guard sessionID == state.session.id else { return false }
        switch action {
        case "start": return state.session.phase == .ready
        case "restart": return !state.session.isActive
        case "pause": return state.session.phase == .running
        case "resume": return state.session.phase == .paused
        case "end": return state.session.isActive
        case "select": return kind != nil && state.presets.contains { $0.kind == kind }
        default: return false
        }
    }
}
