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
    ///
    /// A session saved at its deadline is a guess that nobody paused or ended it first. A change the
    /// other device made after that run began and before its deadline proves the guess wrong, and the
    /// other device's copy wins on both sides.
    @discardableResult mutating func merge(_ remote: SyncEnvelope, at now: Date) -> Bool {
        let before = self, local = changedAt ?? .distantPast
        var overruled = Set<UUID>()
        for record in remote.records {
            if let index = history.firstIndex(where: { $0.id == record.id }) {
                if record.outranks(history[index]) { history[index] = record; overruled.insert(record.id) }
            } else if !(record.id == session.id && record.reachedDeadline && session.disproves(record.lastRun, record.finishedAt, changed: local)) {
                history.append(record)
            }
        }
        if let index = history.firstIndex(where: { $0.id == remote.session.id }), history[index].reachedDeadline,
           remote.session.disproves(history[index].lastRun, history[index].finishedAt, changed: remote.changedAt) {
            history.remove(at: index); overruled.insert(remote.session.id)
        }
        history.sort { $0.startedAt < $1.startedAt }
        if remote.origin == .phone { presets = remote.presets }
        // The same check from the other side: its copy of this session was the guess.
        let guessed = remote.session.reachedDeadline && remote.session.id == session.id
            && remote.session.spans?.last.map { session.disproves($0.start, $0.end, changed: local) } == true
        var finished = Set(history.map(\.id)).union(remote.finishedIDs)
        if guessed { finished.remove(session.id) }
        let gone = finished.union(remote.replacedIDs).union(replacedIDs)
        func stale(_ value: Session) -> Bool { value.isActive && gone.contains(value.id) }
        // On an exact tie the phone's copy wins, so both devices pick the same session.
        let remoteNewer = remote.changedAt > local || (remote.changedAt == local && remote.origin == .phone)
        let takeRemote = overruled.contains(session.id) || !guessed && (stale(session) != stale(remote.session) ? stale(session) : remoteNewer)
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

extension Session {
    /// Finished by reaching its deadline or the stopwatch limit rather than by a tap.
    var reachedDeadline: Bool { (phase == .completed || phase == .ended) && remaining <= 0 }
    /// Whether this copy, changed at `changed`, shows that a run from `start` did not simply reach
    /// `deadline`: it was paused, rescheduled or ended by a tap after the run began and before then.
    func disproves(_ start: Date, _ deadline: Date, changed: Date) -> Bool {
        guard changed > start, changed < deadline, startedAt != nil else { return false }
        return isActive ? end != deadline : !reachedDeadline
    }
}

extension SessionRecord {
    var reachedDeadline: Bool { outcome == .completed || (outcome == .ended && elapsed >= planned - 0.5) }
    var lastRun: Date { spans.last?.start ?? startedAt }
    /// Which of two saves of the same session to keep. A tap is real and beats a deadline guess. Of two
    /// taps the first counts, since the session was over by then. Of two guesses, the one that knew of
    /// more pauses saw the later, real deadline.
    func outranks(_ other: SessionRecord) -> Bool {
        if reachedDeadline != other.reachedDeadline { return other.reachedDeadline }
        if reachedDeadline { return spans.count != other.spans.count ? spans.count > other.spans.count : finishedAt > other.finishedAt }
        return finishedAt < other.finishedAt
    }
}
