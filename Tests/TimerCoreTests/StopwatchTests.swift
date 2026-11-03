import Foundation
import XCTest
@testable import TimerCore

final class StopwatchTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_699_948_800)

    private func stopwatch() -> TimerState {
        var state = TimerState()
        XCTAssertTrue(state.perform("stopwatch", at: now))
        return state
    }

    func testModeSwitchesOnlyWhileIdleAndSurvivesNewSessions() {
        var state = stopwatch()
        XCTAssertTrue(state.session.isUntimed)
        XCTAssertEqual(state.session.elapsed(at: now), 0)
        state.perform("start", at: now)
        XCTAssertFalse(state.perform("timer", at: now.addingTimeInterval(5)))
        XCTAssertFalse(WatchCommand(action: "timer", sessionID: state.session.id).isValid(for: state, at: now))
        XCTAssertTrue(state.session.isUntimed)
        state.perform("reset", at: now.addingTimeInterval(10))
        XCTAssertTrue(state.session.isUntimed)
        state.perform("select", kind: .deepWork, at: now.addingTimeInterval(11))
        XCTAssertTrue(state.session.isUntimed)
        XCTAssertTrue(state.perform("timer", at: now.addingTimeInterval(12)))
        XCTAssertFalse(state.session.isUntimed)
        XCTAssertEqual(state.session.duration, 90 * 60)
    }

    func testStopwatchCountsActiveTimeAndSavesTitleAndMode() {
        var state = stopwatch()
        state.perform("start", title: "  Chapter three  ", at: now)
        XCTAssertEqual(state.session.title, "Chapter three")
        state.perform("pause", at: now.addingTimeInterval(600))
        XCTAssertEqual(state.session.elapsed(at: now.addingTimeInterval(900)), 600, accuracy: 0.001)
        state.perform("resume", at: now.addingTimeInterval(900))
        state.perform("title", title: "Chapter four", at: now.addingTimeInterval(950))
        state.perform("end", at: now.addingTimeInterval(1200))
        let record = state.history.last
        XCTAssertEqual(record?.elapsed ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(record?.title, "Chapter four")
        XCTAssertEqual(record?.isUntimed, true)
        XCTAssertEqual(record?.outcome, .ended)
        XCTAssertNil(state.suggestedNext())
    }

    func testEmptyTitleIsDroppedAndFinishedSessionsCannotBeRenamed() {
        var state = stopwatch()
        state.perform("start", title: "   ", at: now)
        XCTAssertNil(state.session.title)
        state.perform("end", at: now.addingTimeInterval(60))
        XCTAssertFalse(state.perform("title", title: "Late", at: now.addingTimeInterval(61)))
        XCTAssertEqual(TimerState.normalizedTitle(String(repeating: "a", count: 90))?.count, 60)
    }

    func testNameSetBeforeStartFollowsTypeChangesAndResets() {
        var state = stopwatch()
        XCTAssertTrue(state.perform("title", title: "Chapter three", at: now))
        state.perform("select", kind: .deepWork, at: now)
        state.perform("select", kind: .longBreak, at: now)
        XCTAssertEqual(state.session.title, "Chapter three")
        XCTAssertTrue(WatchCommand(action: "title", sessionID: state.session.id, title: "x").isValid(for: state, at: now))
        state.perform("start", at: now)
        state.perform("reset", at: now.addingTimeInterval(30))
        XCTAssertEqual(state.session.title, "Chapter three")
        state.perform("start", at: now.addingTimeInterval(40))
        state.perform("end", at: now.addingTimeInterval(100))
        XCTAssertEqual(state.history.last?.title, "Chapter three")
        state.perform("start", at: now.addingTimeInterval(200))
        XCTAssertNil(state.session.title, "A new session after End starts unnamed")
        state.perform("reset", at: now.addingTimeInterval(201))
        state.perform("title", title: "Kept?", at: now.addingTimeInterval(202))
        state.perform("timer", at: now.addingTimeInterval(203))
        XCTAssertNil(state.session.title, "Switching to the timer drops the stopwatch name")
    }

    func testForgottenStopwatchStopsAtTheLimit() {
        var state = stopwatch()
        state.perform("start", at: now)
        state.reconcile(at: now.addingTimeInterval(Session.stopwatchLimit + 3600))
        XCTAssertEqual(state.session.phase, .ended)
        XCTAssertEqual(state.history.last?.elapsed ?? 0, Session.stopwatchLimit, accuracy: 0.001)
        XCTAssertEqual(state.history.last?.outcome, .ended)
    }

    func testCompletionRateIgnoresStopwatchSessions() {
        var state = TimerState()
        state.perform("start", at: now)
        state.reconcile(at: now.addingTimeInterval(45 * 60 + 1))
        state.perform("stopwatch", at: now.addingTimeInterval(46 * 60))
        state.perform("start", at: now.addingTimeInterval(46 * 60))
        state.perform("end", at: now.addingTimeInterval(50 * 60))
        let stats = SessionStatistics(records: state.history, interval: DateInterval(start: now, duration: 86400))
        XCTAssertEqual(stats.sessions.count, 2)
        XCTAssertEqual(stats.completionRate, 1)
    }

    func testClockRoundsDownForStopwatchAndUpForCountdown() {
        XCTAssertEqual(TimerState.clock(0.4, roundsUp: false), "0:00")
        XCTAssertEqual(TimerState.clock(0.4), "0:01")
        XCTAssertEqual(TimerState.clock(9 * 60 + 45), "9:45", "Minutes match the system timer text in Live Activities")
        XCTAssertEqual(TimerState.clock(3725.9, roundsUp: false), "1:02:05")
    }

    func testBackupAndReportCarryStopwatchSessions() throws {
        var state = stopwatch()
        state.perform("start", title: "Private plan", at: now)
        state.perform("end", at: now.addingTimeInterval(300))
        let backup = try HistoryBackup.decode(HistoryBackup(records: state.history, createdAt: now).encoded())
        XCTAssertEqual(backup.records.first?.title, "Private plan")
        XCTAssertEqual(backup.records.first?.isUntimed, true)
        let hidden = HistoryExport.markdown(records: state.history, now: now, includeNames: false)
        XCTAssertFalse(hidden.contains("Private plan"))
        XCTAssertTrue(hidden.contains("| Focus | stopwatch |"))
        XCTAssertTrue(HistoryExport.markdown(records: state.history, now: now, includeNames: true).contains("Work: Private plan"))
    }

    func testOlderSavesAndSnapshotsStillDecode() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TimerState())) as! [String: Any]
        var session = legacy["session"] as! [String: Any]
        session.removeValue(forKey: "untimed"); session.removeValue(forKey: "title")
        legacy["session"] = session
        let decoded = try JSONDecoder().decode(TimerState.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(decoded.session.isUntimed)
        XCTAssertNil(decoded.session.title)
    }

    func testWatchStartsANamedStopwatchThatThePhoneAdopts() {
        var phone = stopwatch()
        var watch = TimerState(); watch.merge(phone.envelope(from: .phone), at: now)
        XCTAssertTrue(watch.session.isUntimed)
        watch.perform("select", kind: .deepWork, at: now.addingTimeInterval(1))
        XCTAssertTrue(watch.session.isUntimed)
        watch.perform("start", title: "From wrist", at: now.addingTimeInterval(2))
        XCTAssertTrue(phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(3)))
        XCTAssertEqual(phone.session.title, "From wrist")
        XCTAssertEqual(phone.session.phase, .running)
        XCTAssertEqual(phone.selected, .deepWork)
    }
}
