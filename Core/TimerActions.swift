import Foundation

extension TimerState {
    /// One action path for iPhone, Watch and Live Activity controls.
    @discardableResult public mutating func perform(_ action: String, kind: SessionKind? = nil, title: String? = nil, at now: Date) -> Bool {
        switch action {
        case "timer", "stopwatch":
            return setMode(untimed: action == "stopwatch")
        case "title":
            guard session.isActive else { return false }
            session.title = Self.normalizedTitle(title)
        case "reset", "restart":
            // Keep the old wire action as a reset-only alias during app updates.
            return reset(confirmed: true, at: now)
        case "select":
            guard let kind else { return false }
            return select(kind, confirmed: true, at: now)
        case "start":
            reconcile(at: now)
            if session.phase == .completed || session.phase == .ended {
                guard reset(confirmed: true, at: now) else { return false }
            }
            guard session.phase == .ready else { return false }
            if let title { session.title = Self.normalizedTitle(title) }
            start(at: now)
        case "pause": pause(at: now)
        case "resume": resume(at: now)
        case "end": end(at: now)
        default: return false
        }
        return true
    }

    /// A one-tap follow-up after a session completes; nothing starts until the user picks it.
    /// Focus is followed by a short break, or a long break after every fourth focus that day.
    /// A break is followed by the most recent focus session.
    func suggestedNext(calendar: Calendar = .current) -> Preset? {
        guard session.phase == .completed, let finished = history.last(where: { $0.id == session.id }) else { return nil }
        let kind: SessionKind
        if finished.isBreak {
            kind = history.last { !$0.isBreak && presets.contains(kind: $0.preset.kind) }?.preset.kind ?? .work
        } else {
            let focus = history.filter { !$0.isBreak && $0.outcome == .completed && calendar.isDate($0.finishedAt, inSameDayAs: finished.finishedAt) }
            kind = focus.count % 4 == 0 ? .longBreak : .shortBreak
        }
        return presets.first { $0.kind == kind }
    }
}
private extension [Preset] {
    func contains(kind: SessionKind) -> Bool { contains { $0.kind == kind } }
}
