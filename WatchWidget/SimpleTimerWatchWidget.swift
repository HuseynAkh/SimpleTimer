import WidgetKit
import SwiftUI

/// The current session on the watch face or in the Smart Stack: a live countdown or stopwatch beside a
/// small timer mark. The Watch app shares its session through the App Group and reloads this widget when
/// it changes; the system draws the running time from the stored dates, so no frequent reloads are needed.
@main struct SimpleTimerWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimpleTimerLauncher", provider: SessionProvider()) { SessionWidgetView(entry: $0) }
            .configurationDisplayName("SimpleTimer")
            .description("Your timer or stopwatch, live.")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct SessionEntry: TimelineEntry {
    let date: Date
    let session: Session
}

struct SessionProvider: TimelineProvider {
    private var sample: Session { Session(preset: Preset.defaults[0]) }
    func placeholder(in context: Context) -> SessionEntry { SessionEntry(date: .now, session: sample) }
    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        let now = Date()
        completion(SessionEntry(date: now, session: settled(WidgetSession.load() ?? sample, at: now)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let now = Date(), session = WidgetSession.load() ?? sample
        var entries = [SessionEntry(date: now, session: settled(session, at: now))]
        // A countdown that finishes while the app is closed shows as done at its deadline.
        if session.phase == .running, let end = session.end, end > now {
            entries.append(SessionEntry(date: end, session: settled(session, at: end)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
    /// The stored session can outlive its deadline until the Watch app next runs; show it as finished.
    private func settled(_ session: Session, at date: Date) -> Session {
        guard session.phase == .running, let end = session.end, end <= date else { return session }
        var done = session; done.phase = session.isUntimed ? .ended : .completed; done.remaining = 0; done.end = nil
        return done
    }
}

struct SessionWidgetView: View {
    let entry: SessionEntry
    @Environment(\.widgetFamily) private var family
    private var session: Session { entry.session }
    private var symbol: String { session.isUntimed ? "stopwatch" : "timer" }
    private var name: String { session.title ?? session.preset.name }
    /// The running interval, measured from the effective start so pauses stay excluded.
    private var span: ClosedRange<Date>? {
        guard session.phase == .running, let end = session.end else { return nil }
        return end.addingTimeInterval(-session.duration)...end
    }
    private var status: String {
        switch session.phase {
        case .running: session.isUntimed ? "Stopwatch" : session.end.map { "Ends \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        case .paused: "Paused"
        case .ready: "Tap to start"
        case .completed: "Done"
        case .ended: "Ended"
        }
    }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name), \(status)")
    }

    @ViewBuilder private var time: some View {
        if let span {
            Text(timerInterval: span, countsDown: !session.isUntimed, showsHours: true)
        } else if session.isUntimed {
            Text(TimerState.clock(session.elapsed(at: entry.date), roundsUp: false))
        } else {
            Text(TimerState.clock(session.remaining(at: entry.date)))
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            if let span, !session.isUntimed {
                ProgressView(timerInterval: span, countsDown: true) { EmptyView() } currentValueLabel: {
                    Text(timerInterval: span, countsDown: true, showsHours: false).monospacedDigit()
                }.progressViewStyle(.circular).widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).widgetAccentable()
                        time.font(.system(size: 13, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    }.padding(5)
                }
            }
        case .accessoryCorner:
            Image(systemName: symbol).font(.system(size: 22, weight: .medium)).widgetAccentable()
                .widgetLabel { time.monospacedDigit() }
        case .accessoryInline:
            Label { time.monospacedDigit() } icon: { Image(systemName: symbol) }
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).widgetAccentable()
                    Text(name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(status).foregroundStyle(.secondary).lineLimit(1)
                }.font(.system(size: 13, weight: .medium))
                time.font(.system(size: 34, weight: .medium)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1).widgetAccentable()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
