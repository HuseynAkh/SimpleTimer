import Foundation
import XCTest
@testable import TimerCore

final class WatchSyncTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testPushReceiptCompletesSelectionWhenDirectReplyIsLost() throws {
        var phone = TimerState()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, at: now, revision: 1))
        let command = try XCTUnwrap(watch.select(.deepWork, at: now))
        XCTAssertEqual(watch.displayedSession?.preset.kind, .deepWork)
        XCTAssertEqual(watch.snapshot?.session.preset.kind, .work) // Preview is not persisted state.
        phone.select(.deepWork, at: now)
        watch.receive(WatchSnapshot(state: phone, at: now, revision: 2, acknowledgedCommandID: command.id))
        XCTAssertNil(watch.pending)
        XCTAssertNil(watch.desiredSelection)
        XCTAssertFalse(watch.fail(try XCTUnwrap(command.id))) // A late transport error cannot undo success.
        XCTAssertEqual(watch.displayedSession?.id, phone.session.id)
    }

    func testRapidSelectionsCoalesceAndUseTheConfirmedSessionID() throws {
        var phone = TimerState()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, at: now, revision: 1))
        let first = try XCTUnwrap(watch.select(.deepWork, at: now))
        XCTAssertNil(watch.select(.shortBreak, at: now))
        XCTAssertNil(watch.select(.longBreak, at: now))
        XCTAssertEqual(watch.displayedSession?.preset.kind, .longBreak)
        phone.select(.deepWork, at: now)
        watch.receive(WatchSnapshot(state: phone, at: now, revision: 2, acknowledgedCommandID: first.id))
        let last = try XCTUnwrap(watch.nextSelection(at: now))
        XCTAssertEqual(last.kind, .longBreak)
        XCTAssertEqual(last.sessionID, phone.session.id)
        XCTAssertTrue(last.isValid(for: phone, at: now))
        XCTAssertNil(watch.nextSelection(at: now))
    }

    func testLateReplyCannotRevertNewerStateOrFinishAnotherCommand() throws {
        var phone = TimerState()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, at: now, revision: 1))
        let first = try XCTUnwrap(watch.select(.deepWork, at: now))
        phone.select(.deepWork, at: now)
        let firstReply = WatchSnapshot(state: phone, at: now, revision: 2, acknowledgedCommandID: first.id)
        watch.receive(firstReply)
        let second = try XCTUnwrap(watch.begin("start", at: now))
        phone.start(at: now)
        watch.receive(WatchSnapshot(state: phone, at: now, revision: 3))
        watch.reply(to: try XCTUnwrap(first.id), snapshot: firstReply)
        XCTAssertEqual(watch.snapshot?.session.phase, .running)
        XCTAssertEqual(watch.pending?.id, second.id)
    }

    func testTimeoutDropsQueuedSelectionAndNeverReplaysTimerActions() throws {
        let phone = TimerState()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, at: now, revision: 1))
        let command = try XCTUnwrap(watch.select(.deepWork, at: now))
        _ = watch.select(.shortBreak, at: now)
        XCTAssertTrue(watch.fail(try XCTUnwrap(command.id)))
        XCTAssertEqual(watch.displayedSession?.preset.kind, .work)
        XCTAssertNil(watch.nextSelection(at: now))
        watch.receive(WatchSnapshot(state: phone, at: now, revision: 2))
        XCTAssertNil(watch.pending)
        XCTAssertNil(watch.nextSelection(at: now))
    }

    func testLateConfirmationAfterTimeoutShowsWhatActuallyHappened() throws {
        var phone = TimerState()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, at: now, revision: 1))
        let command = try XCTUnwrap(watch.begin("start", at: now))
        watch.fail(try XCTUnwrap(command.id))
        phone.start(at: now)
        watch.receive(WatchSnapshot(state: phone, at: now, revision: 2, acknowledgedCommandID: command.id))
        XCTAssertEqual(watch.displayedSession?.phase, .running)
        XCTAssertNil(watch.pending)
    }

    func testRevisionOrderingSurvivesClockChangesAndIgnoresOldContext() {
        var phone = TimerState()
        var watch = WatchSyncState(snapshot: WatchSnapshot(state: phone, at: now, revision: 5))
        phone.select(.deepWork, at: now)
        XCTAssertTrue(watch.receive(WatchSnapshot(state: phone, at: now.addingTimeInterval(-60), revision: 6)))
        XCTAssertFalse(watch.receive(WatchSnapshot(state: TimerState(), at: now.addingTimeInterval(60), revision: 4)))
        XCTAssertFalse(watch.receive(WatchSnapshot(state: TimerState(), at: now.addingTimeInterval(120))))
        XCTAssertEqual(watch.snapshot?.session.preset.kind, .deepWork)
    }

    func testOldCompanionPayloadsStillDecodeAndReply() throws {
        let state = TimerState()
        let data = try JSONEncoder().encode(WatchSnapshot(state: state, at: now))
        let old = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        XCTAssertNil(old.revision)
        var watch = WatchSyncState(snapshot: old)
        let command = try XCTUnwrap(watch.begin("start", at: now))
        var running = state; running.start(at: now)
        watch.reply(to: try XCTUnwrap(command.id), snapshot: WatchSnapshot(state: running, at: now))
        XCTAssertNil(watch.pending)
        let legacyData = Data("{\"action\":\"start\",\"sessionID\":\"\(state.session.id)\"}".utf8)
        let legacy = try JSONDecoder().decode(WatchCommand.self, from: legacyData)
        XCTAssertNil(legacy.id)
        XCTAssertTrue(legacy.isValid(for: state, at: now))
    }

    func testExpiredCommandsAndStaleSessionCannotChangeThePhone() {
        var phone = TimerState()
        let command = WatchCommand(action: "start", sessionID: phone.session.id, expiresAt: now.addingTimeInterval(8))
        XCTAssertTrue(command.isValid(for: phone, at: now))
        XCTAssertFalse(command.isValid(for: phone, at: now.addingTimeInterval(8)))
        phone.select(.deepWork, at: now)
        XCTAssertFalse(command.isValid(for: phone, at: now))
    }

    @MainActor func testSlowSystemEffectDoesNotBlockNewStateAndOnlyLatestEffectFollows() async {
        let (started, signal) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var applied: [Int] = []
        let queue = LatestEffectsQueue<Int> { value in
            applied.append(value)
            if value == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    signal.yield(())
                }
            }
        }
        queue.submit(1)
        for await _ in started { break }
        queue.submit(2)
        queue.submit(3)
        XCTAssertEqual(applied, [1])
        release?.resume()
        await queue.waitForIdle()
        XCTAssertEqual(applied, [1, 3])
        queue.submit(4)
        await queue.waitForIdle()
        XCTAssertEqual(applied, [1, 3, 4])
        signal.finish()
    }
}
