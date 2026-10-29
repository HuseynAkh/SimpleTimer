import Foundation

public struct SessionKind: RawRepresentable, Codable, Hashable, CaseIterable, Sendable, Identifiable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let work = Self(rawValue: "work")
    public static let deepWork = Self(rawValue: "deepWork")
    public static let shortBreak = Self(rawValue: "shortBreak")
    public static let longBreak = Self(rawValue: "longBreak")
    public static let allCases: [Self] = [.work, .deepWork, .shortBreak, .longBreak]
    public var id: String { rawValue }
    public var isCustom: Bool { !Self.allCases.contains(self) }
    public var name: String { switch rawValue { case "work": "Work"; case "deepWork": "Deep Work"; case "shortBreak": "Short Break"; case "longBreak": "Long Break"; default: "Session" } }
    public var symbol: String { switch rawValue { case "work": "briefcase"; case "deepWork": "scope"; case "shortBreak": "cup.and.saucer"; case "longBreak": "leaf"; default: "timer" } }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}
public struct Preset: Codable, Equatable, Sendable {
    public var kind: SessionKind
    public var minutes: Int
    public var color: String
    public var customName: String?
    public var name: String { customName ?? kind.name }
    public init(kind: SessionKind, minutes: Int, color: String, customName: String? = nil) { self.kind = kind; self.minutes = minutes; self.color = color; self.customName = customName }
    public static let defaults: [Preset] = [.init(kind: .work, minutes: 45, color: "violet"), .init(kind: .deepWork, minutes: 90, color: "orange"), .init(kind: .shortBreak, minutes: 15, color: "teal"), .init(kind: .longBreak, minutes: 60, color: "green")]
}
public enum Phase: String, Codable, Sendable { case ready, running, paused, completed, ended }
public struct Session: Codable, Equatable, Sendable {
    public var id: UUID
    public var preset: Preset
    public var duration: TimeInterval
    public var remaining: TimeInterval
    public var end: Date?
    public var startedAt: Date?
    public var runningSince: Date?
    public var spans: [RunSpan]?
    public var pauseCount: Int?
    public var phase: Phase
    public init(preset: Preset) { id = UUID(); self.preset = preset; duration = Double(preset.minutes * 60); remaining = duration; end = nil; phase = .ready }
    public func remaining(at now: Date) -> TimeInterval { max(0, phase == .running ? (end?.timeIntervalSince(now) ?? remaining) : remaining) }
    public var isActive: Bool { phase == .running || phase == .paused }
}
public struct TimerState: Codable, Equatable, Sendable {
    public var presets = Preset.defaults
    public var selected: SessionKind = .work
    public var session = Session(preset: Preset.defaults[0])
    public var sound = true
    public var haptics = true
    public var history: [SessionRecord] = []
    private enum CodingKeys: String, CodingKey { case presets, selected, session, sound, haptics, history }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        presets = try values.decode([Preset].self, forKey: .presets)
        selected = try values.decode(SessionKind.self, forKey: .selected)
        session = try values.decode(Session.self, forKey: .session)
        sound = try values.decode(Bool.self, forKey: .sound)
        haptics = try values.decode(Bool.self, forKey: .haptics)
        history = try values.decodeIfPresent([SessionRecord].self, forKey: .history) ?? []
    }
    public init() {}
    private mutating func closeSpan(at now: Date) {
        if let start = session.runningSince {
            let end = min(now, session.end ?? now)
            session.spans = (session.spans ?? []) + [RunSpan(start: start, end: end)]
            session.runningSince = nil
        }
    }
    private mutating func archive(_ outcome: SessionOutcome, at now: Date) {
        guard let record = record(outcome: outcome, at: now), !history.contains(where: { $0.id == record.id }) else { return }
        history.append(record)
    }
    private func record(outcome: SessionOutcome, at now: Date) -> SessionRecord? {
        guard let startedAt = session.startedAt else { return nil }
        var spans = session.spans ?? []
        if let start = session.runningSince { spans.append(RunSpan(start: start, end: min(now, session.end ?? now))) }
        return SessionRecord(id: session.id, preset: session.preset, startedAt: startedAt,
                             finishedAt: max(startedAt, now), planned: session.duration, spans: spans,
                             pauses: session.pauseCount ?? 0, outcome: outcome)
    }
    public func records(at now: Date) -> [SessionRecord] {
        var copy = self; copy.reconcile(at: now)
        var records = copy.history
        if copy.session.isActive, !records.contains(where: { $0.id == copy.session.id }),
           let current = copy.record(outcome: copy.session.phase == .running ? .running : .paused, at: now) { records.append(current) }
        return records
    }
    public mutating func reconcile(at now: Date) {
        if session.phase == .running && session.remaining(at: now) <= 0 {
            let finished = session.end ?? now
            closeSpan(at: finished); archive(.completed, at: finished)
            session.phase = .completed; session.remaining = 0; session.end = nil
        }
    }
    public mutating func start(at now: Date) {
        guard session.phase == .ready else { return }
        session.startedAt = now; session.runningSince = now; session.spans = []; session.pauseCount = 0
        session.end = now.addingTimeInterval(session.remaining); session.phase = .running
    }
    public mutating func pause(at now: Date) {
        reconcile(at: now); guard session.phase == .running else { return }
        closeSpan(at: now); session.pauseCount = (session.pauseCount ?? 0) + 1
        session.remaining = session.remaining(at: now); session.end = nil; session.phase = .paused
    }
    public mutating func resume(at now: Date) {
        guard session.phase == .paused else { return }
        if session.startedAt != nil { session.runningSince = now }
        session.end = now.addingTimeInterval(session.remaining); session.phase = .running
    }
    public mutating func end(at now: Date) {
        reconcile(at: now); guard session.isActive else { return }
        closeSpan(at: now); archive(.ended, at: now)
        session.remaining = session.remaining(at: now); session.end = nil; session.phase = .ended
    }
    @discardableResult public mutating func select(_ kind: SessionKind, confirmed: Bool = false, at now: Date = Date()) -> Bool {
        guard !session.isActive || confirmed else { return false }
        guard let preset = presets.first(where: { $0.kind == kind }) else { return false }
        if kind == selected { return reset(confirmed: confirmed, at: now) }
        reconcile(at: now)
        if session.isActive { closeSpan(at: now); archive(.switched, at: now) }
        selected = kind; session = Session(preset: preset); return true
    }
    @discardableResult public mutating func reset(confirmed: Bool = false, at now: Date = Date()) -> Bool {
        guard !session.isActive || confirmed,
              let preset = presets.first(where: { $0.kind == selected }) else { return false }
        // Reset discards only the current attempt. Do not reconcile/archive it,
        // even if its deadline just passed. Previously saved history stays intact.
        session = Session(preset: preset)
        return true
    }
    public mutating func edit(_ preset: Preset) {
        guard (1...240).contains(preset.minutes), let index = presets.firstIndex(where: { $0.kind == preset.kind }) else { return }
        presets[index] = preset
        if session.phase == .ready && selected == preset.kind { session = Session(preset: preset) }
    }
    public mutating func restoreDefaults() { presets = Preset.defaults + presets.filter { $0.kind.isCustom }; if session.phase == .ready { _ = reset() } }
    @discardableResult public mutating func addPreset(name: String, minutes: Int, color: String) -> SessionKind? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, (1...240).contains(minutes) else { return nil }
        let kind = SessionKind(rawValue: "custom-" + UUID().uuidString)
        presets.append(Preset(kind: kind, minutes: minutes, color: color, customName: trimmed))
        return kind
    }
    @discardableResult public mutating func removePreset(_ kind: SessionKind) -> Bool {
        guard kind.isCustom, !(selected == kind && session.isActive) else { return false }
        presets.removeAll { $0.kind == kind }
        if selected == kind { _ = select(.work) }
        return true
    }
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(ceil(max(0, seconds))), h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%02d:%02d", m, s % 60)
    }
}
public struct StateFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var backupURL: URL { url.appendingPathExtension("previous") }
    public func load() throws -> TimerState {
        do { return try JSONDecoder().decode(TimerState.self, from: Data(contentsOf: url)) }
        catch {
            if let data = try? Data(contentsOf: backupURL), let previous = try? JSONDecoder().decode(TimerState.self, from: data) { return previous }
            throw error
        }
    }
    public func save(_ state: TimerState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Retain the previous decodable save; never overwrite it with corrupt data.
        if let prior = try? Data(contentsOf: url), (try? JSONDecoder().decode(TimerState.self, from: prior)) != nil {
            try prior.write(to: backupURL, options: .atomic)
        }
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
