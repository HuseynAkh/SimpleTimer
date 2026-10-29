import Foundation

extension TimerState {
    /// One action path for iPhone, Watch and Live Activity controls.
    @discardableResult public mutating func perform(_ action: String, kind: SessionKind? = nil, at now: Date) -> Bool {
        switch action {
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
            start(at: now)
        case "pause": pause(at: now)
        case "resume": resume(at: now)
        case "end": end(at: now)
        default: return false
        }
        return true
    }
}
