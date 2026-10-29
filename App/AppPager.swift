import SwiftUI

enum AppPage: Int, CaseIterable, Identifiable {
    case activity, timer, settings
    var id: Int { rawValue }
    var title: String { switch self { case .activity: "Activity"; case .timer: "Timer"; case .settings: "Settings" } }
}

struct AppPager: View {
    @EnvironmentObject private var store: TimerStore
    @State private var page: AppPage? = .timer
    private var currentPage: AppPage { page ?? .timer }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(AppPage.allCases) { item in
                        Group {
                            switch item {
                            case .activity: ActivityScreen()
                            case .timer: TimerScreen()
                            case .settings: SettingsScreen()
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .accessibilityHidden(currentPage != item)
                            .id(item)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
        }.clipped()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pageControls.padding(.bottom, 8).padding(.top, 4)
        }
        .background {
            if currentPage == .timer { DashboardBackground(accent: Palette.color(store.state.session.preset.color)) }
            else { AppBackground() }
        }
    }
    private var pageControls: some View {
        HStack(spacing: 0) {
            ForEach(AppPage.allCases) { item in
                Button { select(item) } label: {
                    Capsule().fill(Color.primary.opacity(page == item ? 0.9 : 0.25))
                        .frame(width: page == item ? 18 : 6, height: 6)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("\(item.title), page \(item.rawValue + 1) of 3")
                    .accessibilityAddTraits(page == item ? .isSelected : [])
            }
        }.font(.footnote.weight(.semibold)).buttonStyle(.plain)
            .padding(.horizontal, 4)
            .background {
                if #available(iOS 26.0, *), !opaque, contrast != .increased {
                    Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
                } else { Capsule().fill(Color(UIColor.secondarySystemGroupedBackground)) }
            }
    }
    private func select(_ value: AppPage) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = value }
    }
}
