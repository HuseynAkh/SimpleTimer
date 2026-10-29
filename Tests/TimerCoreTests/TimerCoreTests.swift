import Foundation
#if canImport(XCTest)
import XCTest
@testable import TimerCore
#else
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \(b), got \(a)", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, file: file, line: line) }
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, file: file, line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, file: file, line: line) }
#endif
final class TimerCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10000)
    func testDefaultsAndExplicitStart() { var s = TimerState(); XCTAssertEqual(s.presets.map(\.minutes), [45,90,15,60]); s.select(.deepWork); XCTAssertEqual(s.session.phase, .ready); XCTAssertEqual(s.session.remaining, 5400); XCTAssertEqual(TimerState.clock(5400), "1:30:00") }
    func testRepeatedPauseResume() { var s = TimerState(); s.start(at: now); s.pause(at: now.addingTimeInterval(100)); XCTAssertEqual(s.session.remaining, 2600); s.resume(at: now.addingTimeInterval(500)); s.pause(at: now.addingTimeInterval(550)); XCTAssertEqual(s.session.remaining, 2550); s.resume(at: now.addingTimeInterval(1000)); XCTAssertEqual(s.session.end, now.addingTimeInterval(3550)) }
    func testCompletionNeverAdvances() { for kind in SessionKind.allCases { var s = TimerState(); s.select(kind); s.start(at: now); s.reconcile(at: now.addingTimeInterval(20000)); XCTAssertEqual(s.session.phase, .completed); XCTAssertEqual(s.selected, kind); XCTAssertNil(s.session.end); s.resume(at: now); XCTAssertEqual(s.session.phase, .completed) } }
    func testEditsAndDefaultsPreserveActiveSnapshot() { var s = TimerState(); s.start(at: now); let active = s.session; s.edit(.init(kind: .work, minutes: 12, color: "teal")); XCTAssertEqual(s.session, active); s.restoreDefaults(); XCTAssertEqual(s.session, active) }
    func testDestructiveActionsRequireConfirmation() { var s = TimerState(); s.start(at: now); XCTAssertFalse(s.select(.shortBreak)); XCTAssertFalse(s.reset()); s.pause(at: now); XCTAssertFalse(s.reset()); XCTAssertTrue(s.select(.longBreak, confirmed: true)); XCTAssertEqual(s.session.phase, .ready) }
    func testPersistenceAndRestartRecovery() throws { var s = TimerState(); s.select(.deepWork); s.start(at: now); let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }; let file = StateFile(url: url); try file.save(s); var restored = try file.load(); XCTAssertEqual(restored,s); restored.reconcile(at: now.addingTimeInterval(5401)); XCTAssertEqual(restored.session.phase,.completed) }
    func testPausedRestoration() throws { var s = TimerState(); s.start(at: now); s.pause(at: now.addingTimeInterval(60)); var r = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(s)); r.reconcile(at: now.addingTimeInterval(90000)); XCTAssertEqual(r.session.phase,.paused); XCTAssertEqual(r.session.remaining,2640) }
    func testPauseAtDeadlineCompletes() { var s = TimerState(); s.start(at: now); s.pause(at: now.addingTimeInterval(2700)); XCTAssertEqual(s.session.phase,.completed) }
    func testEndAndResetStayIdle() { var s = TimerState(); s.start(at: now); s.end(at: now.addingTimeInterval(60)); XCTAssertEqual(s.session.phase,.ended); s.reset(); XCTAssertEqual(s.session.phase,.ready); XCTAssertNil(s.session.end) }
    func testCustomSessionPersistenceAndSelection() throws {
        var s = TimerState()
        let kind = s.addPreset(name: " Reading ", minutes: 35, color: "blue")!
        XCTAssertEqual(s.presets.last?.name, "Reading")
        XCTAssertTrue(s.select(kind)); XCTAssertEqual(s.session.remaining, 2100); XCTAssertEqual(s.session.phase, .ready)
        let restored = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(restored, s)
    }
    func testCustomDeletionAndDefaultRestoreProtectActiveSession() {
        var s = TimerState(); let kind = s.addPreset(name: "Reading", minutes: 25, color: "teal")!
        s.select(kind); s.start(at: now); let active = s.session
        XCTAssertFalse(s.removePreset(kind)); s.restoreDefaults(); XCTAssertEqual(s.session, active)
        XCTAssertTrue(s.presets.contains { $0.kind == kind }); s.end(at: now); XCTAssertTrue(s.removePreset(kind)); XCTAssertEqual(s.selected, .work)
        XCTAssertFalse(s.select(kind)); XCTAssertFalse(s.removePreset(.work))
    }
    func testInvalidCustomPresetsAreRejected() {
        var s = TimerState(); XCTAssertNil(s.addPreset(name: "  ", minutes: 25, color: "blue")); XCTAssertNil(s.addPreset(name: "Reading", minutes: 0, color: "blue")); XCTAssertEqual(s.presets.count, 4)
    }

}

#if !canImport(XCTest)
@main struct CoreTestRunner {
    static func main() throws {
        let t = TimerCoreTests()
        t.testDefaultsAndExplicitStart()
        t.testRepeatedPauseResume()
        t.testCompletionNeverAdvances()
        t.testEditsAndDefaultsPreserveActiveSnapshot()
        t.testDestructiveActionsRequireConfirmation()
        try t.testPersistenceAndRestartRecovery()
        try t.testPausedRestoration()
        t.testPauseAtDeadlineCompletes()
        t.testEndAndResetStayIdle()
        try t.testCustomSessionPersistenceAndSelection()
        t.testCustomDeletionAndDefaultRestoreProtectActiveSession()
        t.testInvalidCustomPresetsAreRejected()
        print("PASS: 12 timer core tests (standalone runner; same assertions as XCTest suite)")
    }
}
#endif
