import Foundation
import XCTest
@testable import TimerCore

final class HistoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func testPauseTimeExcludedAndHistoryDeduplicated() {
        var state = TimerState(); state.start(at: now)
        state.pause(at: now.addingTimeInterval(60)); state.resume(at: now.addingTimeInterval(600))
        state.end(at: now.addingTimeInterval(660)); state.end(at: now.addingTimeInterval(700)); state.reconcile(at: now.addingTimeInterval(900))
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history[0].elapsed, 120)
        XCTAssertEqual(state.history[0].pauses, 1)
        XCTAssertEqual(state.history[0].outcome, .ended)
        XCTAssertEqual(state.history[0].finishedAt, now.addingTimeInterval(660))
    }
    func testOverdueRestorationUsesDeadlineNotReopenTime() throws {
        var state = TimerState(); state.start(at: now)
        state.pause(at: now.addingTimeInterval(60)); state.resume(at: now.addingTimeInterval(3600))
        var restored = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(state))
        restored.reconcile(at: now.addingTimeInterval(90_000)); restored.reconcile(at: now.addingTimeInterval(100_000))
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.history[0].finishedAt, now.addingTimeInterval(6240))
        XCTAssertEqual(restored.history[0].elapsed, 2700)
        XCTAssertEqual(restored.history[0].outcome, .completed)
    }
    func testSwitchSavesPartialSessionButResetDiscardsIt() {
        var state = TimerState(); state.start(at: now)
        state.select(.deepWork, confirmed: true, at: now.addingTimeInterval(30))
        XCTAssertEqual(state.history[0].elapsed, 30); XCTAssertEqual(state.history[0].outcome, .switched)
        XCTAssertEqual(state.session.phase, .ready)
        state.start(at: now.addingTimeInterval(40)); state.reset(confirmed: true, at: now.addingTimeInterval(100))
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.session.phase, .ready)
        XCTAssertEqual(state.session.remaining, 5400)
    }
    func testLegacyStateDecodesWithoutInventingHistory() throws {
        var state = TimerState(); state.start(at: now)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json.removeValue(forKey: "history")
        var session = json["session"] as! [String: Any]
        for key in ["startedAt", "runningSince", "spans", "pauseCount"] { session.removeValue(forKey: key) }
        json["session"] = session
        var restored = try JSONDecoder().decode(TimerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.session.remaining(at: now.addingTimeInterval(10)), 2690)
        restored.reconcile(at: now.addingTimeInterval(3000)); XCTAssertTrue(restored.history.isEmpty)
        restored.reset(); restored.start(at: now.addingTimeInterval(4000)); restored.end(at: now.addingTimeInterval(4060))
        XCTAssertEqual(restored.history.count, 1)
    }
    func testLiveSnapshotAndCompletionAreNotDoubleCounted() {
        var state = TimerState(); state.start(at: now)
        XCTAssertEqual(state.records(at: now.addingTimeInterval(15))[0].elapsed, 15)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.records(at: now.addingTimeInterval(9000))[0].elapsed, 2700)
        state.reconcile(at: now.addingTimeInterval(9000))
        XCTAssertEqual(state.records(at: now.addingTimeInterval(9000)).count, 1)
    }
    func testOvernightTimeSplitIntoCorrectDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 23, minute: 50))!
        var state = TimerState(); state.start(at: start); state.end(at: start.addingTimeInterval(1200))
        let day = ReportPeriod.day.interval(containing: start, calendar: calendar)
        let next = ReportPeriod.day.interval(containing: start.addingTimeInterval(1200), calendar: calendar)
        XCTAssertEqual(SessionStatistics(records: state.history, interval: day).total, 600)
        XCTAssertEqual(SessionStatistics(records: state.history, interval: next).total, 600)
        XCTAssertEqual(SessionStatistics(records: state.history, interval: day).buckets(unit: .hour, calendar: calendar).reduce(0) { $0 + $1.total }, 600)
    }
    func testDSTDayHas23Or25Hours() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let report = SessionStatistics(records: [], interval: ReportPeriod.day.interval(containing: date, calendar: calendar))
            XCTAssertEqual(report.buckets(unit: .hour, calendar: calendar).count, hours)
        }
    }
    func testDeletedCustomPresetPreservesHistoryAndColor() throws {
        var state = TimerState(); let kind = state.addPreset(name: "Reading", minutes: 20, color: "rose")!
        state.select(kind); state.start(at: now); state.end(at: now.addingTimeInterval(180))
        XCTAssertTrue(state.removePreset(kind))
        let restored = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.history[0].preset.name, "Reading"); XCTAssertEqual(restored.history[0].preset.color, "rose")
    }
    func testSummaryCompletionAndBreakSeparation() {
        var state = TimerState(); state.start(at: now); state.reconcile(at: now.addingTimeInterval(2700))
        state.select(.shortBreak); state.start(at: now.addingTimeInterval(3000)); state.end(at: now.addingTimeInterval(3060))
        let report = SessionStatistics(records: state.history, interval: DateInterval(start: now, duration: 10_000))
        XCTAssertEqual(report.total, 2760); XCTAssertEqual(report.focus, 2700); XCTAssertEqual(report.rest, 60)
        XCTAssertEqual(report.completionRate, 0.5); XCTAssertEqual(report.averageSession, 1380)
        XCTAssertEqual(report.longest, 2700)
    }
}
