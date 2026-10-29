import SwiftUI

@main struct SimpleTimerWatchApp: App {
    @StateObject private var store = WatchStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchTimerScreen().environmentObject(store)
                .onChange(of: phase) { _, value in if value == .active { store.refresh() } }
        }
    }
}
struct WatchTimerScreen: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if let message = store.message {
                        Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let session = store.displayedSession {
                        Text(session.preset.name).font(.headline).foregroundStyle(.secondary)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(TimerState.clock(session.remaining(at: context.date)))
                                .font(.system(.largeTitle, design: .rounded).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                                .accessibilityLabel("Time remaining")
                        }
                        if session.phase == .paused { Text("Paused").font(.caption) }
                        Button {
                            store.perform(session.phase == .running ? "pause" : session.phase == .paused ? "resume" : "start")
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
                                    .accessibilityHint("Restores the full duration without saving this session.")
                            }
                        }
                        NavigationLink("Sessions") {
                            WatchSessionsScreen()
                        }
                        Text("iPhone timer").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "iphone.and.arrow.forward").font(.largeTitle)
                        Text("Open SimpleTimer on iPhone").multilineTextAlignment(.center)
                    }
                    if store.busy { ProgressView().accessibilityLabel("Updating timer") }
                }.padding(.horizontal, 6)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { store.refresh(manual: true) } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh from iPhone").disabled(store.refreshing) } }
        }
    }
}

private struct WatchSessionsScreen: View {
    // Observe the store in the pushed screen itself; a captured navigation
    // destination can otherwise keep the selection from when it was opened.
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        List(store.snapshot?.presets ?? [], id: \.kind) { preset in
            WatchSessionRow(preset: preset, selected: preset.kind == store.displayedSession?.preset.kind) {
                store.perform("select", kind: preset.kind)
            }
        }
        .navigationTitle("Sessions")
        .safeAreaInset(edge: .bottom) {
            if let message = store.message {
                Text(message).font(.caption2).multilineTextAlignment(.center)
                    .padding(6).background(.ultraThinMaterial)
            }
        }
    }
}

private struct WatchSessionRow: View {
    let preset: Preset
    let selected: Bool
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
                    Text("\(preset.minutes) min").font(.caption).foregroundStyle(.white.opacity(0.85))
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
        .accessibilityLabel("\(preset.name), \(preset.minutes) minutes")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
