import SwiftUI

/// The always-visible menu bar item: compact icon+number pairs for CPU,
/// Memory, Disk and Network, refreshed on the same timer as the rest of
/// the app so it costs nothing extra to sample.
struct MenuBarLabelView: View {
    @EnvironmentObject var model: TaskManagerViewModel

    var body: some View {
        HStack(spacing: 6) {
            metric("cpu", Format.percent(model.system.cpuPercent))
            metric("memorychip", Format.percent(model.totalMemoryPercent))
            metric("internaldrive", Format.compactRate(model.system.diskReadBytesPerSec + model.system.diskWriteBytesPerSec))
            metric("network", Format.compactRate(model.system.networkInBytesPerSec + model.system.networkOutBytesPerSec))
            if let temp = model.system.cpuTemperatureCelsius {
                metric("thermometer.medium", Format.celsius(temp))
            }
        }
        .font(.system(size: 12, weight: .regular).monospacedDigit())
    }

    private func metric(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 11))
            Text(value)
        }
    }
}

/// The dropdown panel when the menu bar item is clicked: the same four
/// numbers at a readable size, plus quick access to the full window.
struct MenuBarContentView: View {
    @EnvironmentObject var model: TaskManagerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("CPU", "cpu", Format.percent(model.system.cpuPercent), model.system.cpuPercent / 100)
            row("Memory", "memorychip", Format.percent(model.totalMemoryPercent), model.totalMemoryPercent / 100)
            row(
                "Disk", "internaldrive",
                Format.bytesPerSecond(model.system.diskReadBytesPerSec + model.system.diskWriteBytesPerSec),
                nil
            )
            row(
                "Network", "network",
                Format.megabitsPerSecond(model.system.networkInBytesPerSec + model.system.networkOutBytesPerSec),
                nil
            )
            if let temp = model.system.cpuTemperatureCelsius {
                row("Temperature", "thermometer.medium", Format.celsius(temp), temp / 100)
            }

            Divider()

            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open Task Manager", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Task Manager", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 220)
    }

    @ViewBuilder
    private func row(_ title: String, _ symbol: String, _ value: String, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}
