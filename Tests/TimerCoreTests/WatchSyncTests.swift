import Foundation
import XCTest
@testable import TimerCore

final class WatchSyncTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    // Older Watch builds still read revision-ordered snapshots while both apps update.
    func testRevisionOrderingSurvivesClockChangesAndIgnoresOldContext() {
        var phone = TimerState()
        let first = WatchSnapshot(state: phone, at: now, revision: 5)
        phone.select(.deepWork, at: now)
        let newer = WatchSnapshot(state: phone, at: now.addingTimeInterval(-60), revision: 6)
        XCTAssertTrue(newer.isNewer(than: first))
        XCTAssertFalse(WatchSnapshot(state: TimerState(), at: now.addingTimeInterval(60), revision: 4).isNewer(than: newer))
        XCTAssertFalse(WatchSnapshot(state: TimerState(), at: now.addingTimeInterval(120)).isNewer(than: newer))
    }

    func testOldCompanionPayloadsStillDecode() throws {
        let state = TimerState()
        let data = try JSONEncoder().encode(WatchSnapshot(state: state, at: now))
        XCTAssertNil(try JSONDecoder().decode(WatchSnapshot.self, from: data).revision)
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
