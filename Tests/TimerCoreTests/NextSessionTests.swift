import Foundation
import XCTest
@testable import TimerCore

final class NextSessionTests: XCTestCase {
    // 08:00 UTC, so four rounds stay on one calendar day.
    let now = Date(timeIntervalSince1970: 1_699_948_800)
    var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "UTC")!; return value }

    private func complete(_ state: inout TimerState, _ kind: SessionKind, at start: Date) -> Date {
        if state.selected != kind { state.perform("select", kind: kind, at: start) }
        state.perform("start", at: start)
        let end = start.addingTimeInterval(state.session.duration + 1)
        state.reconcile(at: end)
        return end
    }

    func testFocusSuggestsShortBreakThenLongBreakOnTheFourth() {
        var state = TimerState(), cursor = now
        for round in 1...4 {
            cursor = complete(&state, .work, at: cursor)
            XCTAssertEqual(state.suggestedNext(calendar: calendar)?.kind, round == 4 ? .longBreak : .shortBreak)
            cursor = complete(&state, .shortBreak, at: cursor)
        }
    }

    func testBreakSuggestsTheLastFocusSession() {
        var state = TimerState()
        let end = complete(&state, .deepWork, at: now)
        _ = complete(&state, .shortBreak, at: end)
        XCTAssertEqual(state.suggestedNext(calendar: calendar)?.kind, .deepWork)
    }

    func testOnlyCompletedSessionsGetASuggestion() {
        var state = TimerState()
        XCTAssertNil(state.suggestedNext(calendar: calendar))
        state.perform("start", at: now)
        XCTAssertNil(state.suggestedNext(calendar: calendar))
        state.perform("end", at: now.addingTimeInterval(60))
        XCTAssertNil(state.suggestedNext(calendar: calendar))
    }

    func testResetAfterCompletionClearsTheSuggestion() {
        var state = TimerState()
        _ = complete(&state, .work, at: now)
        state.perform("reset", at: now.addingTimeInterval(4000))
        XCTAssertNil(state.suggestedNext(calendar: calendar))
    }
}
