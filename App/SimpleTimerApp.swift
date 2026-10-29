import SwiftUI

@main struct SimpleTimerApp: App {
    @StateObject private var store = TimerStore.shared
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if store.storageAvailable { AppPager().environmentObject(store) }
                else { ContentUnavailableView("Saved data needs recovery", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your files have been kept unchanged. Recover them from the app container before continuing.")) }
            }
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { _ in Task { await store.refresh() } }
                .task { PhoneConnection.shared.start(); await store.refresh() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        }
    }
}
