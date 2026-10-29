import AppIntents
import Foundation

struct TimerControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control SimpleTimer"
    static var description = IntentDescription("Pause, resume, end or reset the current SimpleTimer session.")
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Action") var action: String
    init() {}
    init(sessionID: UUID, action: String) { self.sessionID = sessionID.uuidString; self.action = action }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = TimerStore.shared
        guard store.state.session.id.uuidString == sessionID, ["pause", "resume", "end", "reset"].contains(action) else { return .result() }
        await store.perform(action)
        #endif
        return .result()
    }
}
