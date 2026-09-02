import SwiftUI

struct SettingsView: View {
    @AppStorage(MenuBarPreferenceKey.showCPU) private var showCPU = true
    @AppStorage(MenuBarPreferenceKey.showMemory) private var showMemory = true
    @AppStorage(MenuBarPreferenceKey.showDisk) private var showDisk = true
    @AppStorage(MenuBarPreferenceKey.showNetwork) private var showNetwork = true
    @AppStorage(MenuBarPreferenceKey.showTemperature) private var showTemperature = true

    var body: some View {
        Form {
            Section {
                Toggle("CPU", isOn: $showCPU)
                Toggle("Memory", isOn: $showMemory)
                Toggle("Disk", isOn: $showDisk)
                Toggle("Network", isOn: $showNetwork)
                Toggle("Temperature", isOn: $showTemperature)
            } header: {
                Text("Show in Menu Bar")
            } footer: {
                Text("The dropdown panel always shows every metric, whatever's picked here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 260)
    }
}
