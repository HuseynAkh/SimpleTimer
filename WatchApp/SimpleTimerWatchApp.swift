import SwiftUI

@main struct SimpleTimerWatchApp: App {
    @StateObject private var store = WatchStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchTimerScreen().environmentObject(store)
                .onChange(of: phase) { _, value in if value == .active { store.refresh() } }
        }
        .backgroundTask(.watchConnectivity) { await store.finishBackgroundDelivery() }
    }
}
struct WatchTimerScreen: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.legibilityWeight) private var legibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var screenHeight: CGFloat = 0
    var body: some View {
        let session = store.session
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: 8) {
                        Text(session.title ?? session.preset.name).font(.headline).foregroundStyle(.secondary).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let shown = session.isUntimed ? TimerState.clock(session.elapsed(at: context.date), roundsUp: false) : TimerState.clock(session.remaining(at: context.date))
                            Text(shown)
                                // Light SF Pro digits match the iPhone timer and Live Activity.
                                .font(.system(.largeTitle).weight(legibility == .bold ? .medium : .light).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                                .contentTransition(.numericText(countsDown: !session.isUntimed)).animation(reduceMotion ? nil : .snappy, value: shown)
                                .accessibilityLabel(session.isUntimed ? "Time elapsed" : "Time remaining")
                                .onChange(of: session.remaining(at: context.date) <= 0) { _, done in if done && session.phase == .running { store.refresh() } }
                        }
                        if let status = session.phase == .paused ? "Paused" : session.phase == .ended ? "Ended" : session.phase == .completed ? "Complete" : nil {
                            Text(status).font(.caption)
                        }
                        // Changes always apply here first; this only appears while the iPhone is out of reach.
                        if store.unsynced && store.away {
                            Label("Syncs with iPhone later", systemImage: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.secondary)
                        }
                        // The name is optional and set before a stopwatch starts; the iPhone can rename it later.
                        if session.isUntimed && !session.isActive {
                            TextField("Name", text: $name).accessibilityLabel("Session name")
                        }
                        Button {
                            let action = session.phase == .running ? "pause" : session.phase == .paused ? "resume" : "start"
                            // An empty field keeps any name already set on iPhone.
                            store.perform(action, title: action == "start" && session.isUntimed && !name.isEmpty ? name : nil)
                            if action == "start" { name = "" }
                        } label: {
                            Label(session.phase == .running ? "Pause" : session.phase == .paused ? "Resume" : "Start", systemImage: session.phase == .running ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(.black)
                            .background(Palette.color(session.preset.color), in: Capsule())
                        if session.isActive {
                            HStack(spacing: 8) {
                                Button(role: .destructive) { store.perform("end") } label: {
                                    Text("End").frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.plain).foregroundStyle(.red)
                                    .background(.red.opacity(0.15), in: Capsule())
                                Button { store.perform("reset") } label: {
                                    Text("Reset").frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.plain)
                                    .background(.white.opacity(0.15), in: Capsule())
                                    .accessibilityHint(session.isUntimed ? "Clears this stopwatch without saving." : "Restores the full duration without saving this session.")
                            }
                        }
                    }
                    // While a session runs, the clock and controls fill the screen and Sessions waits below the fold.
                    // A minimum, not a fixed height, so a status or sync line can still push the controls down.
                    .frame(minHeight: session.isActive ? screenHeight : nil, alignment: .top)
                    NavigationLink { WatchSessionsScreen() } label: {
                        Text("Sessions").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain)
                        .background(.white.opacity(0.15), in: Capsule())
                }.padding(.horizontal, 6)
            }
            // Scrolling content also shows under the bottom inset, so Sessions starts past the screen edge.
            .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { screenHeight = $0 }
            .toolbar {
                // Mode changes only between sessions, matching the iPhone.
                if !session.isActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.perform(session.isUntimed ? "timer" : "stopwatch") } label: { Image(systemName: session.isUntimed ? "timer" : "stopwatch") }
                            .accessibilityLabel(session.isUntimed ? "Switch to timer" : "Switch to stopwatch")
                    }
                }
            }
        }
    }
}

private struct WatchSessionsScreen: View {
    // Observe the store in the pushed screen itself; a captured navigation
    // destination can otherwise keep the selection from when it was opened.
    @EnvironmentObject private var store: WatchStore
    @State private var switching: Preset?

    var body: some View {
        List(store.state.presets, id: \.kind) { preset in
            WatchSessionRow(preset: preset, selected: preset.kind == store.session.preset.kind, untimed: store.session.isUntimed) {
                if store.session.isActive { switching = preset } else { store.perform("select", kind: preset.kind) }
            }
        }
        .navigationTitle("Sessions")
        .confirmationDialog("Switch to \(switching?.name ?? "")?", isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }), titleVisibility: .visible, presenting: switching) { preset in
            Button("Switch") { store.perform("select", kind: preset.kind) }
        } message: { _ in Text("Your current session is saved.") }
    }
}

private struct WatchSessionRow: View {
    let preset: Preset
    let selected: Bool
    let untimed: Bool
    let select: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            // Keep the current session readable and avoid resetting it when tapped.
            if !selected { select() }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name).font(.body.weight(selected ? .semibold : .regular))
                    if !untimed { Text(durationLabel(preset.minutes)).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.color(preset.color).opacity(selected ? 0.32 : 0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selected ? (contrast == .increased ? .white : Palette.color(preset.color)) : .clear, lineWidth: contrast == .increased ? 2 : 1.5)
                }
        )
        .accessibilityLabel(untimed ? preset.name : "\(preset.name), \(durationLabel(preset.minutes))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
