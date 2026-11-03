import Foundation

public enum SyncOrigin: String, Codable, Sendable { case phone, watch }

/// What each device sends the other. Either device changes its copy at once and sends this when it can;
/// neither waits for the other before showing or saving a change.
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public var origin: SyncOrigin
    public var session: Session
    public var presets: [Preset]
    public var changedAt: Date
    /// Sessions the Watch finished that the phone has not acknowledged yet. The phone sends none.
    public var records: [SessionRecord]
    /// Recently finished session IDs from the phone. They acknowledge Watch records and stop a
    /// session that already ended on one device from running again on the other.
    public var finishedIDs: [UUID]
    /// Sessions the sender replaced on purpose.
    public var replacedIDs: [UUID]
}

public extension TimerState {
    func envelope(from origin: SyncOrigin, finishedLimit: Int = 100) -> SyncEnvelope {
        let recent = history.sorted { $0.finishedAt > $1.finishedAt }.prefix(finishedLimit).map(\.id)
        return SyncEnvelope(origin: origin, session: session, presets: presets, changedAt: changedAt ?? .distantPast,
                            records: origin == .watch ? history : [], finishedIDs: origin == .phone ? Array(recent) : [], replacedIDs: replacedIDs)
    }

    /// Converges two copies: history is a union by session ID, the phone owns the presets, and the
    /// newest change to the current session wins. A session that one side already saved never
    /// becomes active again, and a session this side was still running is saved as switched rather
    /// than dropped when the other side's newer session wins.
    @discardableResult mutating func merge(_ remote: SyncEnvelope, at now: Date) -> Bool {
        let before = self
        var known = Set(history.map(\.id))
        let added = remote.records.filter { known.insert($0.id).inserted }
        if !added.isEmpty { history.append(contentsOf: added); history.sort { $0.startedAt < $1.startedAt } }
        if remote.origin == .phone { presets = remote.presets }
        let finished = known.union(remote.finishedIDs)
        let gone = finished.union(remote.replacedIDs).union(replacedIDs)
        func stale(_ value: Session) -> Bool { value.isActive && gone.contains(value.id) }
        let local = changedAt ?? .distantPast
        // On an exact tie the phone's copy wins, so both devices pick the same session.
        let remoteNewer = remote.changedAt > local || (remote.changedAt == local && remote.origin == .phone)
        let takeRemote = stale(session) != stale(remote.session) ? stale(session) : remoteNewer
        if takeRemote && remote.session != session {
            if remote.session.id != session.id && session.isActive && !gone.contains(session.id) {
                let at = min(now, max(remote.changedAt, session.startedAt ?? remote.changedAt))
                reconcile(at: at)
                if session.isActive { closeSpan(at: at); archive(.switched, at: at) }
            }
            session = remote.session; selected = remote.session.preset.kind; changedAt = remote.changedAt
        } else if stale(session) {
            // Both copies were saved elsewhere; show the result instead of a timer that already ended.
            session.phase = .ended; session.end = nil; session.runningSince = nil
        }
        reconcile(at: now)
        return self != before
    }
}
