import WidgetKit
import SwiftUI

/// A launcher for watch faces and the Smart Stack. It shows no timer state, so it needs no shared
/// container; a tap opens SimpleTimer ready to start.
@main struct SimpleTimerWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimpleTimerLauncher", provider: LauncherProvider()) { _ in LauncherView() }
            .configurationDisplayName("SimpleTimer")
            .description("Open your timer.")
            .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct LauncherEntry: TimelineEntry { let date: Date }

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) { completion(LauncherEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        content.containerBackground(.fill.tertiary, for: .widget).accessibilityLabel("Open SimpleTimer")
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "timer").font(.title2.weight(.medium)).widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "timer").font(.title2.weight(.medium)).widgetAccentable().widgetLabel("SimpleTimer")
        case .accessoryInline:
            Label("SimpleTimer", systemImage: "timer")
        default:
            HStack(spacing: 10) {
                Image(systemName: "timer").font(.title2.weight(.medium)).widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text("SimpleTimer").font(.headline)
                    Text("Open timer").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
