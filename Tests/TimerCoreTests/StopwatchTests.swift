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

    func testEmptyTitleIsDroppedAndRenameNeedsAnActiveSession() {
        var state = stopwatch()
        XCTAssertFalse(state.perform("title", title: "Early", at: now))
        state.perform("start", title: "   ", at: now)
        XCTAssertNil(state.session.title)
        XCTAssertEqual(TimerState.normalizedTitle(String(repeating: "a", count: 90))?.count, 60)
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
        XCTAssertEqual(TimerState.clock(0.4, roundsUp: false), "00:00")
        XCTAssertEqual(TimerState.clock(0.4), "00:01")
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

    func testWatchSelectionPreviewKeepsStopwatchMode() {
        var phone = stopwatch()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, revision: 1))
        _ = watch.select(.deepWork, at: now)
        XCTAssertEqual(watch.displayedSession?.isUntimed, true)
        let start = WatchCommand(action: "start", sessionID: phone.session.id, title: "From wrist")
        XCTAssertTrue(start.isValid(for: phone, at: now))
        phone.perform(start.action, title: start.title, at: now)
        XCTAssertEqual(phone.session.title, "From wrist")
        XCTAssertTrue(WatchCommand(action: "title", sessionID: phone.session.id, title: "Renamed").isValid(for: phone, at: now))
    }
}
