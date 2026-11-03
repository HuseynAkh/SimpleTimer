import Foundation
import XCTest
@testable import TimerCore

final class SyncTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_699_948_800)

    private func paired() -> (phone: TimerState, watch: TimerState) {
        var phone = TimerState(); phone.changedAt = now
        var watch = TimerState(); watch.merge(phone.envelope(from: .phone), at: now)
        return (phone, watch)
    }

    func testWatchActsAloneAndThePhoneCatchesUp() {
        var (phone, watch) = paired()
        XCTAssertEqual(watch.session, phone.session)
        watch.perform("start", at: now.addingTimeInterval(10))
        watch.perform("pause", at: now.addingTimeInterval(70))
        // Delivered late: the phone applies the Watch's state as of when it happened.
        XCTAssertTrue(phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(600)))
        XCTAssertEqual(phone.session.phase, .paused)
        XCTAssertEqual(phone.session.elapsed(at: now.addingTimeInterval(600)), 60, accuracy: 0.001)
        XCTAssertFalse(watch.merge(phone.envelope(from: .phone), at: now.addingTimeInterval(601)), "Echoes change nothing")
    }

    func testWatchRecordsReachThePhoneOnceAndAreAcknowledged() {
        var (phone, watch) = paired()
        watch.perform("start", at: now)
        watch.perform("end", at: now.addingTimeInterval(300))
        phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(400))
        phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(500))
        XCTAssertEqual(phone.history.count, 1)
        XCTAssertEqual(phone.history.first?.elapsed ?? 0, 300, accuracy: 0.001)
        let ack = phone.envelope(from: .phone)
        XCTAssertTrue(ack.finishedIDs.contains(watch.history[0].id))
        XCTAssertTrue(ack.records.isEmpty)
    }

    func testNewestChangeWinsAndTheLosingRunningSessionIsSaved() {
        var (phone, watch) = paired()
        phone.perform("start", at: now.addingTimeInterval(10))
        // The Watch never heard about that start and picks another type later.
        watch.perform("select", kind: .shortBreak, at: now.addingTimeInterval(100))
        phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(120))
        XCTAssertEqual(phone.session.preset.kind, .shortBreak)
        XCTAssertEqual(phone.history.last?.outcome, .switched)
        XCTAssertEqual(phone.history.last?.elapsed ?? 0, 90, accuracy: 0.001)
        watch.merge(phone.envelope(from: .phone), at: now.addingTimeInterval(121))
        XCTAssertEqual(watch.session, phone.session)
    }

    func testAnEndedSessionNeverRunsAgain() {
        var (phone, watch) = paired()
        phone.perform("start", at: now)
        watch.merge(phone.envelope(from: .phone), at: now)
        phone.perform("end", at: now.addingTimeInterval(60))
        // The Watch, still offline, pauses later than the phone ended.
        watch.perform("pause", at: now.addingTimeInterval(90))
        phone.merge(watch.envelope(from: .watch), at: now.addingTimeInterval(100))
        XCTAssertEqual(phone.session.phase, .ended)
        watch.merge(phone.envelope(from: .phone), at: now.addingTimeInterval(101))
        XCTAssertEqual(watch.session.phase, .ended)
        XCTAssertFalse(watch.session.isActive)
    }

    func testBothDevicesCompleteTheSameDeadlineWithoutDuplicates() {
        var (phone, watch) = paired()
        phone.perform("start", at: now)
        watch.merge(phone.envelope(from: .phone), at: now)
        let later = now.addingTimeInterval(45 * 60 + 5)
        phone.reconcile(at: later); watch.reconcile(at: later)
        XCTAssertEqual(phone.changedAt, watch.changedAt)
        phone.merge(watch.envelope(from: .watch), at: later)
        XCTAssertEqual(phone.history.count, 1)
        XCTAssertEqual(phone.session.phase, .completed)
    }

    func testPhoneOwnsPresetsAndTiesFavourThePhone() {
        var (phone, watch) = paired()
        phone.edit(Preset(kind: .work, minutes: 30, color: "blue"))
        watch.presets[0].minutes = 5
        watch.changedAt = phone.changedAt
        watch.merge(phone.envelope(from: .phone), at: now)
        XCTAssertEqual(watch.presets[0].minutes, 30)
        XCTAssertEqual(watch.session, phone.session)
        var other = phone
        XCTAssertFalse(other.merge(watch.envelope(from: .watch), at: now), "The Watch never overrides phone presets")
    }

    func testOlderSavesWithoutAChangeTimeLoseToAnyRealChange() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TimerState())) as! [String: Any]
        legacy.removeValue(forKey: "changedAt")
        var watch = try JSONDecoder().decode(TimerState.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(watch.changedAt)
        var phone = TimerState(); phone.perform("select", kind: .longBreak, at: now)
        watch.merge(phone.envelope(from: .phone), at: now)
        XCTAssertEqual(watch.session.preset.kind, .longBreak)
    }
}
