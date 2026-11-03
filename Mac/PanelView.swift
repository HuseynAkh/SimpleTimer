import AppKit
import SwiftUI

extension Session {
    var primaryAction: String { switch phase { case .running: "pause"; case .paused: "resume"; case .ready, .completed, .ended: "start" } }
}

/// The drop-down: one clock, one large action and the session types, in the iPhone's design language.
struct PanelView: View {
    @ObservedObject var store: MacStore
    var rendering = false
    @State private var switching: Preset?
    @FocusState private var naming: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var session: Session { store.state.session }
    private var untimed: Bool { session.isUntimed }
    private var accent: Color { Palette.color(session.preset.color) }

    var body: some View {
        VStack(spacing: 16) {
            clock
            controls.animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: session.isActive)
            if let switching { confirm(switching) } else { chips }
            footer
        }
        .padding(16).frame(width: 300)
        .background { PanelBackground(accent: accent, material: !rendering) }
    }
    private var clock: some View {
        let shown = untimed ? TimerState.clock(session.elapsed(at: store.now), roundsUp: false) : TimerState.clock(session.remaining(at: store.now))
        return VStack(spacing: 2) {
            if untimed { nameField.padding(.bottom, 6) }
            Text(shown).font(.system(size: 56, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText(countsDown: !untimed)).animation(reduceMotion ? nil : .snappy, value: shown)
                .accessibilityLabel(untimed ? "Time elapsed" : "Time remaining").accessibilityValue(shown)
            Text(status ?? " ").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 4)
        // The mode switch only appears between sessions.
        .overlay(alignment: .topTrailing) { if !session.isActive { modeButton } }
    }
    private var nameField: some View {
        TextField("Name this session", text: $store.draft)
            .textFieldStyle(.plain).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            .focused($naming).onSubmit { naming = false }
            .onChange(of: naming) { _, focused in if !focused { store.commitDraft() } }
            .onChange(of: store.draft) { _, value in if value.count > 60 { store.draft = String(value.prefix(60)) } }
            .padding(.horizontal, 12).frame(width: 196, height: 32)
            .background(Color.primary.opacity(naming ? 0.1 : 0.06), in: Capsule())
            .accessibilityLabel("Session name")
    }
    private var modeButton: some View {
        Button { store.act(untimed ? "timer" : "stopwatch") } label: {
            Image(systemName: untimed ? "timer" : "stopwatch").font(.body.weight(.medium)).frame(width: 30, height: 30).contentShape(Circle())
        }.buttonStyle(Press()).background(Color.primary.opacity(0.08), in: Circle())
            .help(untimed ? "Timer" : "Stopwatch").accessibilityLabel(untimed ? "Switch to timer" : "Switch to stopwatch")
    }
    /// One large primary action. End and Reset join it as round buttons only while a session is active.
    private var controls: some View {
        HStack(spacing: 12) {
            if session.isActive { round("End", symbol: "stop.fill", action: "end") }
            Button { store.act(session.primaryAction) } label: {
                Label(primaryTitle, systemImage: session.phase == .running ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46).contentShape(Capsule())
            }.buttonStyle(Press()).foregroundStyle(scheme == .dark ? Color.black : .white).background(accent, in: Capsule())
            if session.isActive { round("Reset", symbol: "arrow.counterclockwise", action: "reset") }
        }
    }
    private func round(_ title: String, symbol: String, action: String) -> some View {
        Button { store.act(action) } label: {
            Image(systemName: symbol).imageScale(symbol == "stop.fill" ? .small : .medium).font(.title3.weight(.semibold))
                .frame(width: 46, height: 46).contentShape(Circle())
        }.buttonStyle(Press()).background(Color.primary.opacity(0.08), in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
            .help(title).accessibilityLabel(title)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
    private var chips: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(store.state.presets, id: \.kind) { chip($0) }
        }
    }
    private func chip(_ preset: Preset) -> some View {
        let selected = preset.kind == store.state.selected, tint = Palette.color(preset.color)
        return Button {
            guard !selected else { return }
            // A stray click must not end a running session.
            if session.isActive { switching = preset } else { store.act("select", kind: preset.kind) }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                    if !untimed { Text(durationLabel(preset.minutes)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)).accessibilityHidden(true) }
            }.padding(.horizontal, 12).frame(height: 42).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(Press())
            .background(tint.opacity(selected ? 0.22 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? tint.opacity(0.65) : .clear))
            .contextMenu {
                ForEach([15, 25, 30, 45, 60, 90], id: \.self) { minutes in
                    Toggle(durationLabel(minutes), isOn: Binding(get: { preset.minutes == minutes }, set: { _ in store.setMinutes(minutes, for: preset.kind) }))
                }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func confirm(_ preset: Preset) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Switch to \(preset.name)?").font(.callout.weight(.semibold))
                Text("Your current session is saved.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { switching = nil } label: { Text("Cancel").frame(maxWidth: .infinity, minHeight: 32) }
                    .buttonStyle(Press()).background(Color.primary.opacity(0.08), in: Capsule())
                Button { store.act("select", kind: preset.kind); switching = nil } label: {
                    Text("Switch").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(Press()).foregroundStyle(scheme == .dark ? Color.black : .white).background(Palette.color(preset.color), in: Capsule())
            }
        }.frame(maxWidth: .infinity, minHeight: 92)
    }
    private var footer: some View {
        let focus = SessionStatistics(records: store.state.records(at: store.now), interval: ReportPeriod.day.interval(containing: store.now)).focus
        return HStack {
            Text(store.notice ?? "\(focused(focus)) focused today").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(Press()).font(.caption).foregroundStyle(.secondary).keyboardShortcut("q")
        }
        .padding(.top, 12).overlay(alignment: .top) { Divider() }
    }
    private var status: String? {
        switch session.phase {
        case .ready: untimed ? "Stopwatch" : nil
        case .running where untimed: session.startedAt.map { "Started \($0.formatted(date: .omitted, time: .shortened))" }
        case .running: session.end.map { "Ends \($0.formatted(date: .omitted, time: .shortened))" }
        case .paused: "Paused"; case .completed: "Complete"; case .ended: "Ended"
        }
    }
    private var primaryTitle: String { switch session.phase { case .running: "Pause"; case .paused: "Resume"; case .ready, .completed, .ended: "Start" } }
    private func focused(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h" + (minutes % 60 > 0 ? " \(minutes % 60)m" : "") : "\(minutes)m"
    }
}

private struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.6 : 1) }
}

/// The system popover material, so the drop-down follows Light and Dark Mode and Reduce Transparency,
/// with the iPhone dashboard's faint accent glow.
private struct PanelBackground: View {
    var accent: Color
    var material: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            if material { Material() } else { Color(red: 0.11, green: 0.115, blue: 0.13) }
            RadialGradient(colors: [accent.opacity(scheme == .dark ? 0.2 : 0.1), .clear], center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: 260)
        }
        .clipShape(shape).overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
    }
    private struct Material: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView(); view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
            return view
        }
        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}

#if DEBUG
extension PanelView {
    /// `--render-panel <path>` writes the drop-down with a synthetic running session to a PNG, then quits.
    /// Rendering in-process needs no screen recording permission and never captures the desktop.
    @MainActor static func render(to url: URL) {
        let calendar = Calendar.current, day = calendar.startOfDay(for: Date())
        func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date { day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second)) }
        var state = TimerState()
        state.perform("select", kind: .deepWork, at: at(7, 20)); state.perform("start", at: at(7, 20)); state.reconcile(at: at(8, 51))
        state.perform("select", kind: .work, at: at(9, 0)); state.perform("start", at: at(9, 0))
        let view = PanelView(store: MacStore(file: nil, state: state, now: at(9, 26, 18)), rendering: true).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        guard let image = renderer.cgImage, let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(destination, image, nil)
        exit(CGImageDestinationFinalize(destination) ? 0 : 1)
    }
}
#endif
