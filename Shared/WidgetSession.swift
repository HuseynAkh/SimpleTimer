import Foundation

/// The Watch app's current session, shared with its widget through the App Group. The widget only
/// reads it; times are drawn by the system from the stored dates, so they stay live without reloads.
enum WidgetSession {
    /// The group is derived from the bundle ID, so each developer's own `SIMPLETIMER_BUNDLE_ID` works.
    static var defaults: UserDefaults? {
        guard var base = Bundle.main.bundleIdentifier else { return nil }
        for suffix in [".widget", ".watchkitapp"] where base.hasSuffix(suffix) { base.removeLast(suffix.count) }
        return UserDefaults(suiteName: "group." + base)
    }
    static func load() -> Session? {
        defaults?.data(forKey: "session").flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }
    /// Returns true when the stored session changed, so callers reload widgets only then.
    @discardableResult static func save(_ session: Session) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(session), data != defaults.data(forKey: "session") else { return false }
        defaults.set(data, forKey: "session")
        return true
    }
}
