import Foundation
import XCTest
@testable import TimerCore

final class ExportTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func finished() -> TimerState {
        var state = TimerState(); state.start(at: now); state.pause(at: now.addingTimeInterval(60))
        state.resume(at: now.addingTimeInterval(120)); state.end(at: now.addingTimeInterval(180))
        return state
    }
    func testBackupRoundTripMergeIsIdempotentAndPreservesActiveTimer() throws {
        let source = finished()
        let backup = try HistoryBackup.decode(HistoryBackup(records: source.history, createdAt: now).encoded())
        var target = TimerState(); target.start(at: now)
        let active = target.session
        XCTAssertEqual(target.mergeHistory(backup), 1)
        XCTAssertEqual(target.mergeHistory(backup), 0)
        XCTAssertEqual(target.session, active)
        XCTAssertEqual(target.history[0].elapsed, 120)
        XCTAssertEqual(target.presets, Preset.defaults)
    }
    func testBackupOmitsProvisionalSessionAndRejectsUnknownVersion() throws {
        var state = TimerState(); state.start(at: now)
        XCTAssertTrue(HistoryBackup(records: state.records(at: now.addingTimeInterval(60))).records.isEmpty)
        let data = try HistoryBackup(records: finished().history).encoded()
        let changed = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        XCTAssertThrowsError(try HistoryBackup.decode(Data(changed.utf8)))
    }
    func testReportRedactsNamesAndKeepsActiveSeconds() {
        var state = finished(); state.history[0].preset.customName = "Private | project\nname"
        let report = HistoryExport.markdown(records: state.history, now: now, includeNames: false)
        XCTAssertFalse(report.contains("Private")); XCTAssertTrue(report.contains("120 seconds"))
        let named = HistoryExport.markdown(records: state.history, now: now, includeNames: true)
        XCTAssertTrue(named.contains("Private \\| project name"))
    }
    func testBackupRejectsOverlappingSpans() throws {
        var records = finished().history
        records[0].spans.append(records[0].spans[0])
        XCTAssertThrowsError(try HistoryBackup.decode(HistoryBackup(records: records).encoded()))
    }
    func testDamagedPrimaryRecoversPreviousAndDoesNotDestroyIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StateFile(url: directory.appendingPathComponent("state.json"))
        let original = finished(); try file.save(original)
        var newer = original; newer.sound = false; try file.save(newer)
        try Data("broken".utf8).write(to: file.url)
        XCTAssertEqual(try file.load(), original)
        try file.save(original)
        XCTAssertEqual(try file.load(), original)
        XCTAssertEqual(try JSONDecoder().decode(TimerState.self, from: Data(contentsOf: file.backupURL)), original)
    }
    func testStaleWatchCommandCannotAffectNewSession() {
        var state = TimerState()
        let command = WatchCommand(action: "start", sessionID: state.session.id)
        XCTAssertTrue(command.isValid(for: state))
        state.select(.deepWork)
        XCTAssertFalse(command.isValid(for: state))
        XCTAssertFalse(WatchCommand(action: "delete", sessionID: state.session.id).isValid(for: state))
    }
}
