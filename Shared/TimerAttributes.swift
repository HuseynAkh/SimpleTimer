import ActivityKit
import SwiftUI

struct TimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var end: Date?
        var remaining: Double
        var duration: Double
        // Optional so an activity started by an older build still decodes.
        var untimed: Bool?
        var title: String?
    }
    var sessionID: UUID
    var name: String
    var symbol: String
    var color: String
}
