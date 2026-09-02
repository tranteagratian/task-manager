import SwiftUI

private enum Tab: String, CaseIterable, Identifiable {
    case processes = "Processes"
    case performance = "Performance"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .processes: return "square.grid.2x2"
        case .performance: return "chart.xyaxis.line"
        }
    }
}

/// Tabs Windows 11 has that aren't real macOS concepts (Services, CPU
/// affinity) or need a privileged helper (per-process network) — shown
/// disabled so the sidebar reads like the real thing without faking data.
private enum PlannedTab: String, CaseIterable, Identifiable {
    case appHistory = "App history"
    case startupApps = "Startup apps"
    case users = "Users"
    case details = "Details"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appHistory: return "clock.arrow.circlepath"
        case .startupApps: return "power"
        case .users: return "person.2"
        case .details: return "list.bullet"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: TaskManagerViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedTab: Tab = .processes

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                sidebarButton(title: tab.rawValue, systemImage: tab.systemImage, isSelected: tab == selectedTab) {
                    selectedTab = tab
                }
            }
            Divider().padding(.vertical, 6)
            ForEach(PlannedTab.allCases) { tab in
                sidebarButton(title: tab.rawValue, systemImage: tab.systemImage, isSelected: false, enabled: false) {}
            }
            Spacer()
            sidebarButton(title: "Settings", systemImage: "gearshape", isSelected: false) {
                openSettings()
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .frame(width: 56)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarButton(title: String, systemImage: String, isSelected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .frame(width: 40, height: 36)
                .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? (isSelected ? Color.accentColor : Color.primary) : Color(nsColor: .tertiaryLabelColor))
        .disabled(!enabled)
        .help(title)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .processes: ProcessesView()
        case .performance: PerformanceView()
        }
    }
}
