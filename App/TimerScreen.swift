import SwiftUI

struct TimerScreen: View {
    @EnvironmentObject private var store: TimerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 70.0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.legibilityWeight) private var legibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var switching: Preset?
    private var session: Session { store.state.session }
    private var accent: Color { Palette.chartColor(session.preset.color) }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = session.remaining(at: context.date)
                    ZStack {
                        Circle().stroke(contrast == .increased ? Color(UIColor.separator) : accent.opacity(0.18), lineWidth: 6)
                        Circle().trim(from: 0, to: max(0, min(1, remaining / session.duration)))
                            .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 12) {
                            Text(TimerState.clock(remaining))
                                .font(.system(size: clockSize, weight: legibility == .bold || contrast == .increased ? .medium : .light)).monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                                .contentTransition(.numericText(countsDown: true)).animation(reduceMotion ? nil : .snappy, value: TimerState.clock(remaining))
                                .accessibilityLabel("Time remaining").accessibilityValue(TimerState.clock(remaining))
                            if let status { Text(status).font(.subheadline).foregroundStyle(.secondary) }
                        }.padding(22)
                    }.frame(width: typeSize.isAccessibilitySize ? 300 : 280, height: typeSize.isAccessibilitySize ? 300 : 280)
                        .background { Circle().fill(scheme == .dark ? Color.black.opacity(0.16) : Color.white.opacity(0.48)) }
                        .padding(.vertical, 4)
                        // Fire on the first tick past the deadline; a tick inside the last
                        // second would reconcile too early and leave the timer at 00:00.
                        .onChange(of: remaining <= 0) { _, done in
                            if done && session.phase == .running { Task { await store.refresh() } }
                        }
                }
                controls.animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15), value: session.isActive)
                if let next = store.state.suggestedNext() { suggestion(next) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(store.state.presets, id: \.kind) { preset in
                        Button {
                            guard preset.kind != store.state.selected else { return }
                            // A stray tap must not end a running session.
                            if session.isActive { switching = preset } else { act("select", kind: preset.kind) }
                        } label: {
                            HStack(spacing: 9) {

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name).font(.body.weight(preset.kind == store.state.selected ? .semibold : .regular))
                                    Text(durationLabel(preset.minutes)).font(.caption).foregroundStyle(.secondary)
                                }.multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if preset.kind == store.state.selected { Image(systemName: "checkmark").font(.footnote.weight(.semibold)).accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity, minHeight: 70).padding(.horizontal, 18).contentShape(RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(.plain)
                            .modifier(GlassSurface(shape: .rounded(24), tint: Palette.color(preset.color).opacity(preset.kind == store.state.selected ? 0.22 : 0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(preset.kind == store.state.selected ? Palette.chartColor(preset.color).opacity(0.65) : .clear, lineWidth: 1).allowsHitTesting(false))
                            .accessibilityAddTraits(preset.kind == store.state.selected ? .isSelected : [])
                    }
                }.padding(.top, 10)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let focus = SessionStatistics(records: store.state.records(at: context.date), interval: ReportPeriod.day.interval(containing: context.date)).focus
                    if focus >= 60 { Text("\(activityDuration(focus)) focused today").font(.footnote).foregroundStyle(.secondary).monospacedDigit() }
                }
            }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .disabled(store.busy)
        .alert("Timer notice", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .confirmationDialog("Switch to \(switching?.name ?? "")?", isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }), titleVisibility: .visible, presenting: switching) { preset in
            Button("Switch") { act("select", kind: preset.kind) }
        } message: { _ in Text("Your current session is saved.") }
        .sensoryFeedback(.success, trigger: session.phase == .completed) { _, new in new && store.state.haptics }
        .sensoryFeedback(.impact(weight: .light), trigger: session.phase) { old, new in store.state.haptics && old != new && new != .completed }
    }
    private func suggestion(_ next: Preset) -> some View {
        Button {
            Task { await store.perform("select", kind: next.kind); await store.perform("start") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: next.kind.symbol).foregroundStyle(Palette.chartColor(next.color)).accessibilityHidden(true)
                Text(next.name).font(.subheadline.weight(.semibold))
                Text(durationLabel(next.minutes)).font(.subheadline).foregroundStyle(.secondary)
                Image(systemName: "play.fill").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }.padding(.horizontal, 18).frame(minHeight: 44).contentShape(Capsule())
        }.buttonStyle(.plain)
            .modifier(GlassSurface(shape: .capsule, tint: Palette.color(next.color).opacity(0.12)))
            .accessibilityLabel("Start \(next.name), \(durationLabel(next.minutes))")
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    /// One large primary action. End and Reset join it as round icon buttons only while a session is active.
    @ViewBuilder private var controls: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                primaryButton
                if session.isActive {
                    secondary("End", symbol: "stop.fill", action: "end", labelled: true)
                    secondary("Reset", symbol: "arrow.counterclockwise", action: "reset", labelled: true)
                }
            }
        } else {
            HStack(spacing: 14) {
                if session.isActive { secondary("End", symbol: "stop.fill", action: "end").transition(.scale(scale: 0.6).combined(with: .opacity)) }
                primaryButton
                if session.isActive { secondary("Reset", symbol: "arrow.counterclockwise", action: "reset").transition(.scale(scale: 0.6).combined(with: .opacity)) }
            }
        }
    }
    private var primaryButton: some View {
        Button { act(primaryAction) } label: {
            Label(primaryTitle, systemImage: session.phase == .running ? "pause.fill" : "play.fill")
                .font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 64).contentShape(Capsule())
        }.modifier(PrimaryTimerButton(accent: accent))
    }
    private func secondary(_ title: String, symbol: String, action: String, labelled: Bool = false) -> some View {
        Button { act(action) } label: {
            Group {
                if labelled { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 54) }
                else { Image(systemName: symbol).imageScale(symbol == "stop.fill" ? .small : .medium).frame(width: 64, height: 64) }
            }.font(.title3.weight(.semibold)).foregroundStyle(.primary).contentShape(Capsule())
        }.buttonStyle(.plain).modifier(GlassSurface(shape: labelled ? .capsule : .circle))
            .accessibilityLabel(title)
            .accessibilityHint(action == "reset" ? "Restores the full duration without saving this session." : "Saves this session to your history.")
    }
    private var status: String? {
        switch session.phase {
        case .ready: nil
        case .running: session.end.map { "Ends \($0.formatted(date: .omitted, time: .shortened))" }
        case .paused: "Paused"; case .completed: "Complete"; case .ended: "Ended"
        }
    }
    private var primaryTitle: String { switch session.phase { case .running: "Pause"; case .paused: "Resume"; case .completed, .ended: "Start"; case .ready: "Start" } }
    private var primaryAction: String { switch session.phase { case .running: "pause"; case .paused: "resume"; case .completed, .ended, .ready: "start" } }
    private func act(_ action: String, kind: SessionKind? = nil) { Task { await store.perform(action, kind: kind) } }
}
