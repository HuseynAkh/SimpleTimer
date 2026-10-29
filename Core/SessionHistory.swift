import Foundation

public struct RunSpan: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = max(start, end) }
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public func duration(in interval: DateInterval) -> TimeInterval {
        max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
    }
}
public enum SessionOutcome: String, Codable, Sendable { case completed, ended, reset, switched, running, paused }
public struct SessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var preset: Preset
    public var startedAt: Date
    public var finishedAt: Date
    public var planned: TimeInterval
    public var spans: [RunSpan]
    public var pauses: Int
    public var outcome: SessionOutcome
    public var elapsed: TimeInterval { spans.reduce(0) { $0 + $1.duration } }
    public var isBreak: Bool { preset.kind == .shortBreak || preset.kind == .longBreak }
    public var isFinished: Bool { outcome != .running && outcome != .paused }
    public func duration(in interval: DateInterval) -> TimeInterval { spans.reduce(0) { $0 + $1.duration(in: interval) } }
}
public enum ReportPeriod: String, CaseIterable, Sendable { case day = "Day", week = "Week", month = "Month"
    public var component: Calendar.Component { switch self { case .day: .day; case .week: .weekOfYear; case .month: .month } }
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)!
    }
}
public struct TimeBucket: Identifiable, Equatable {
    public var start: Date
    public var end: Date
    public var focus: TimeInterval
    public var rest: TimeInterval
    public var id: Date { start }
    public var total: TimeInterval { focus + rest }
}
public struct SessionStatistics {
    public let records: [SessionRecord]
    public let interval: DateInterval
    public init(records: [SessionRecord], interval: DateInterval) { self.records = records; self.interval = interval }
    public var sessions: [SessionRecord] {
        records.filter { $0.duration(in: interval) > 0 || ($0.startedAt >= interval.start && $0.startedAt < interval.end) }
    }
    public var total: TimeInterval { records.reduce(0) { $0 + $1.duration(in: interval) } }
    public var focus: TimeInterval { records.filter { !$0.isBreak }.reduce(0) { $0 + $1.duration(in: interval) } }
    public var rest: TimeInterval { total - focus }
    public var completed: Int { sessions.filter { $0.outcome == .completed }.count }
    public var completionRate: Double? {
        let finished = sessions.filter(\.isFinished)
        return finished.isEmpty ? nil : Double(completed) / Double(finished.count)
    }
    public var averageSession: TimeInterval { sessions.isEmpty ? 0 : total / Double(sessions.count) }
    public var longest: TimeInterval { sessions.map { $0.duration(in: interval) }.max() ?? 0 }
    public func buckets(unit: Calendar.Component, calendar: Calendar = .current) -> [TimeBucket] {
        var result: [TimeBucket] = []; var cursor = interval.start
        while cursor < interval.end {
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor), next > cursor else { break }
            let end = min(next, interval.end), slice = DateInterval(start: cursor, end: end)
            let focus = records.filter { !$0.isBreak }.reduce(0) { $0 + $1.duration(in: slice) }
            let rest = records.filter(\.isBreak).reduce(0) { $0 + $1.duration(in: slice) }
            result.append(TimeBucket(start: cursor, end: end, focus: focus, rest: rest)); cursor = end
        }
        return result
    }
    public static func streak(records: [SessionRecord], now: Date, calendar: Calendar = .current) -> Int {
        let focus = records.filter { !$0.isBreak }
        guard let first = focus.flatMap(\.spans).map(\.start).min() else { return 0 }
        var cursor = calendar.startOfDay(for: now), count = 0
        while cursor >= calendar.startOfDay(for: first) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            let seconds = focus.reduce(0) { $0 + $1.duration(in: DateInterval(start: cursor, end: next)) }
            if seconds >= 60 { count += 1 } else if cursor != calendar.startOfDay(for: now) || count > 0 { break }
            cursor = previous
        }
        return count
    }
}
