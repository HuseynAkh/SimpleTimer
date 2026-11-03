import Foundation
import XCTest
@testable import TimerCore

final class ResetTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRunningAndPausedResetDiscardOnlyTheCurrentAttempt() throws {
        for paused in [false, true] {
            var state = TimerState()
            state.perform("start", at: now)
            state.perform("end", at: now.addingTimeInterval(60))
            let history = state.history
            state.perform("start", at: now.addingTimeInterval(100))
            let discardedID = state.session.id
            if paused { state.perform("pause", at: now.addingTimeInterval(140)) }
            state.perform("reset", at: now.addingTimeInterval(200))
            XCTAssertEqual(state.history, history)
            XCTAssertEqual(state.session.phase, .ready)
            XCTAssertEqual(state.session.remaining, state.session.duration)
            XCTAssertNil(state.session.end)
            XCTAssertNil(state.session.startedAt)
            XCTAssertNotEqual(state.session.id, discardedID)
            var restored = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(state))
            restored.reconcile(at: now.addingTimeInterval(100_000))
            XCTAssertEqual(restored.session.phase, .ready)
            XCTAssertEqual(restored.records(at: now.addingTimeInterval(100_000)), history)
        }
    }

    func testResetAtOrAfterDeadlineDoesNotArchiveAnUnfinishedAttempt() {
        for elapsed in [2700.0, 9000.0] {
            var state = TimerState(); state.perform("start", at: now)
            state.perform("reset", at: now.addingTimeInterval(elapsed))
            XCTAssertTrue(state.history.isEmpty)
            XCTAssertTrue(state.records(at: now.addingTimeInterval(elapsed + 1)).isEmpty)
            XCTAssertEqual(state.session.phase, .ready)
        }
    }

    func testLegacyRestartAndSelectingSameSessionAreResetOnly() {
        for action in ["restart", "select"] {
            var state = TimerState(); state.perform("start", at: now)
            state.perform(action, kind: .work, at: now.addingTimeInterval(60))
            XCTAssertEqual(state.session.phase, .ready)
            XCTAssertTrue(state.history.isEmpty)
            XCTAssertNil(state.session.end)
        }
    }

    func testExplicitStartAfterResetTracksOnlyNewElapsedTime() {
        var state = TimerState(); state.perform("start", at: now)
        state.perform("pause", at: now.addingTimeInterval(60))
        state.perform("reset", at: now.addingTimeInterval(300))
        state.perform("start", at: now.addingTimeInterval(600))
        state.perform("end", at: now.addingTimeInterval(630))
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history[0].elapsed, 30)
        XCTAssertEqual(state.history[0].startedAt, now.addingTimeInterval(600))
    }

    func testExplicitStartAfterEndOrCompletionPreservesSavedHistory() {
        for completed in [false, true] {
            var state = TimerState(); state.perform("start", at: now)
            if completed { state.reconcile(at: now.addingTimeInterval(2700)) }
            else { state.perform("end", at: now.addingTimeInterval(60)) }
            let history = state.history
            XCTAssertTrue(WatchCommand(action: "start", sessionID: state.session.id).isValid(for: state))
            state.perform("start", at: now.addingTimeInterval(3000))
            XCTAssertEqual(state.history, history)
            XCTAssertEqual(state.session.phase, .running)
            XCTAssertEqual(state.session.remaining(at: now.addingTimeInterval(3000)), 2700)
        }
    }

    func testWatchResetSyncsWithoutSavingAndRejectsOldCommands() {
        var phone = TimerState(); phone.perform("start", at: now)
        var watch = TimerState(); watch.merge(phone.envelope(from: .phone), at: now)
        let oldCommand = WatchCommand(action: "pause", sessionID: phone.session.id)
        watch.perform("reset", at: now.addingTimeInterval(30))
        XCTAssertEqual(watch.session.phase, .ready)
        phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(31))
        XCTAssertEqual(phone.session.phase, .ready)
        XCTAssertEqual(phone.session.id, watch.session.id)
        XCTAssertTrue(phone.history.isEmpty)
        XCTAssertFalse(oldCommand.isValid(for: phone, at: now.addingTimeInterval(31)))
    }
}
