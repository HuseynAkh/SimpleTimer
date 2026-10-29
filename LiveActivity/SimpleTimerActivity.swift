import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@main struct SimpleTimerWidgets: WidgetBundle {
    var body: some Widget { SimpleTimerLiveActivity() }
}
struct SimpleTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                heading(context)
                HStack(spacing: 12) {
                    countdown(context)
                        .font(.system(size: 42, weight: .light)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    controls(context)
                }
                progress(context)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .activityBackgroundTint(.black.opacity(0.28))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(URL(string: "simpletimer://timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { heading(context).padding(.leading, 4) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            countdown(context)
                                .font(.system(size: 38, weight: .light)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.65)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            controls(context)
                        }
                        progress(context)
                    }.padding(.horizontal, 4).padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "paused" ? "pause" : "timer")
                    .foregroundStyle(Palette.color(context.attributes.color))
            } compactTrailing: {
                countdown(context).monospacedDigit().font(.caption2).frame(maxWidth: 72)
            } minimal: {
                Image(systemName: context.state.phase == "paused" ? "pause" : "timer")
                    .foregroundStyle(Palette.color(context.attributes.color))
            }.widgetURL(URL(string: "simpletimer://timer")).keylineTint(Palette.color(context.attributes.color))
        }
    }
    private func heading(_ context: ActivityViewContext<TimerAttributes>) -> some View {
        HStack(spacing: 7) {
            Circle().fill(Palette.color(context.attributes.color)).frame(width: 6, height: 6)
            Text(context.attributes.name).font(.subheadline.weight(.medium)).lineLimit(1)
            if context.state.phase == "paused" {
                Text("· Paused").foregroundStyle(.secondary).font(.caption)
            } else if context.state.phase == "completed" || context.isStale {
                Text("· Complete").foregroundStyle(.secondary).font(.caption)
            }
        }
    }
    @ViewBuilder private func controls(_ context: ActivityViewContext<TimerAttributes>) -> some View {
        if context.state.phase == "running" || context.state.phase == "paused" {
            HStack(spacing: 8) {
                control(context, action: context.state.phase == "paused" ? "resume" : "pause",
                        symbol: context.state.phase == "paused" ? "play.fill" : "pause.fill",
                        label: context.state.phase == "paused" ? "Resume" : "Pause")
                control(context, action: "end", symbol: "xmark", label: "End timer")
            }
        }
    }
    private func control(_ context: ActivityViewContext<TimerAttributes>, action: String, symbol: String, label: String) -> some View {
        Button(intent: TimerControlIntent(sessionID: context.attributes.sessionID, action: action)) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).modifier(ActivityGlassControl()).accessibilityLabel(label)
    }
    @ViewBuilder private func progress(_ context: ActivityViewContext<TimerAttributes>) -> some View {
        if let end = context.state.end, context.state.phase == "running" {
            ProgressView(timerInterval: end.addingTimeInterval(-context.state.duration)...end, countsDown: true)
                .labelsHidden().tint(Palette.color(context.attributes.color))
        } else {
            ProgressView(value: max(0, min(1, context.state.remaining / context.state.duration)))
                .tint(Palette.color(context.attributes.color))
        }
    }
    @ViewBuilder private func countdown(_ context: ActivityViewContext<TimerAttributes>) -> some View {
        if let end = context.state.end, context.state.phase == "running" {
            Text(timerInterval: end.addingTimeInterval(-context.state.duration)...end, countsDown: true, showsHours: true)
        } else { Text(TimerState.clock(context.state.remaining)) }
    }
}
private struct ActivityGlassControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @ViewBuilder func body(content: Content) -> some View {
        content
            .background(.white.opacity(opaque ? 0.25 : 0.12), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5).allowsHitTesting(false))
    }
}
