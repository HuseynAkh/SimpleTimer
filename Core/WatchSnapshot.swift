import Foundation

/// The phone owns the timer. The watch gets a small read-only snapshot, never history.
public struct WatchSnapshot: Codable, Sendable {
    public let session: Session
    public let presets: [Preset]
    public let updatedAt: Date
    public init(state: TimerState, at date: Date = Date()) { session = state.session; presets = state.presets; updatedAt = date }
}
public struct WatchCommand: Codable, Sendable {
    public let action: String
    public let sessionID: UUID
    public let kind: SessionKind?
    public init(action: String, sessionID: UUID, kind: SessionKind? = nil) { self.action = action; self.sessionID = sessionID; self.kind = kind }
    public func isValid(for state: TimerState) -> Bool {
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
