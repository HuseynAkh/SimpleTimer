import SwiftUI

struct TimerScreen: View {
    @EnvironmentObject private var store: TimerStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 70.0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.legibilityWeight) private var legibility
    private var session: Session { store.state.session }
    private var accent: Color { Palette.chartColor(session.preset.color) }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = session.remaining(at: context.date)
                    ZStack {
                        Circle().stroke(Color(UIColor.separator), lineWidth: 3)
                        Circle().trim(from: 0, to: max(0, min(1, remaining / session.duration)))
                            .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 12) {
                            Text(TimerState.clock(remaining))
                                .font(.system(size: clockSize, weight: legibility == .bold || contrast == .increased ? .medium : .light)).monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                                .accessibilityLabel("Time remaining").accessibilityValue(TimerState.clock(remaining))
                            if let status { Text(status).font(.subheadline).foregroundStyle(.secondary) }
                        }.padding(22)
                    }.frame(width: typeSize.isAccessibilitySize ? 300 : 280, height: typeSize.isAccessibilitySize ? 300 : 280)
                        .background { Circle().fill(scheme == .dark ? Color.black.opacity(0.16) : Color.white.opacity(0.48)) }
                        .padding(.vertical, 4)
                        .onChange(of: Int(remaining)) { _, value in
                            if value == 0 && session.phase == .running { Task { await store.refresh() } }
                        }
                }
                let controlLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 10))
                controlLayout {
                    if !typeSize.isAccessibilitySize || session.isActive {
                        control("End", action: "end", prominent: false)
                            .opacity(session.isActive ? 1 : 0).disabled(!session.isActive).accessibilityHidden(!session.isActive)
                    }
                    control(primaryTitle, action: primaryAction, prominent: true)
                    if !typeSize.isAccessibilitySize || session.isActive {
                        control("Restart", action: "restart", prominent: false)
                            .opacity(session.isActive ? 1 : 0).disabled(!session.isActive).accessibilityHidden(!session.isActive)
                    }
                }.frame(maxWidth: .infinity)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(store.state.presets, id: \.kind) { preset in
                        Button {
                            guard preset.kind != store.state.selected else { return }
                            act("select", kind: preset.kind)
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
            }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .disabled(store.busy)
        .alert("Timer notice", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .sensoryFeedback(.success, trigger: session.phase == .completed) { _, new in new && store.state.haptics }
    }
    private func control(_ title: String, action: String, prominent: Bool) -> some View {
        Button { act(action) } label: {
            Text(title).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }.modifier(PrimaryTimerButton(accent: accent, prominent: prominent))
    }
    private var status: String? { switch session.phase { case .ready, .running: nil; case .paused: "Paused"; case .completed: "Complete"; case .ended: "Ended" } }
    private var primaryTitle: String { switch session.phase { case .running: "Pause"; case .paused: "Resume"; case .completed, .ended: "Start"; case .ready: "Start" } }
    private var primaryAction: String { switch session.phase { case .running: "pause"; case .paused: "resume"; case .completed, .ended: "restart"; case .ready: "start" } }
    private func act(_ action: String, kind: SessionKind? = nil) { Task { await store.perform(action, kind: kind) } }
}
func durationLabel(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60) hr" + (minutes % 60 > 0 ? " \(minutes % 60) min" : "") : "\(minutes) min" }
