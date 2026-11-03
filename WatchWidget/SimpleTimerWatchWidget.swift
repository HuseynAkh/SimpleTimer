import WidgetKit
import SwiftUI

/// A launcher for watch faces and the Smart Stack: the timer and stopwatch symbols, no text. It shows
/// no timer state, so it needs no shared container; a tap opens SimpleTimer ready to start.
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
    /// Symbols only, as large as each slot allows; the face already shows which app it opens.
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                glyph("timer").padding(9)
            }
        case .accessoryCorner:
            glyph("timer").padding(2)
        case .accessoryInline:
            Image(systemName: "timer")
        default:
            HStack(spacing: 18) {
                glyph("timer")
                glyph("stopwatch")
            }.padding(.vertical, 4).frame(maxWidth: .infinity)
        }
    }
    private func glyph(_ name: String) -> some View {
        Image(systemName: name).resizable().scaledToFit().fontWeight(.medium).widgetAccentable()
    }
}
