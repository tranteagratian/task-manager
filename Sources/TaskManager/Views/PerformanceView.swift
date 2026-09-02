import Charts
import SwiftUI
import TaskManagerCore

private enum PerformanceMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case network = "Network"
    case temperature = "Temperature"
    var id: String { rawValue }
}

struct PerformanceView: View {
    @EnvironmentObject var model: TaskManagerViewModel
    @State private var selected: PerformanceMetric = .cpu

    var body: some View {
        HStack(spacing: 0) {
            List(PerformanceMetric.allCases, selection: $selected) { metric in
                MetricTile(metric: metric, isSelected: metric == selected)
                    .tag(metric)
                    .onTapGesture { selected = metric }
            }
            .listStyle(.sidebar)
            .frame(width: 260)

            Divider()

            DetailPane(metric: selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(model)
    }
}

private struct MetricTile: View {
    @EnvironmentObject var model: TaskManagerViewModel
    let metric: PerformanceMetric
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Sparkline(values: history)
                .frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.rawValue).font(.title3)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var history: [Double] {
        switch metric {
        case .cpu: return model.cpuHistory.values
        case .memory: return model.memoryHistory.values
        case .disk: return model.diskHistory.values
        case .network: return model.networkHistory.values
        case .temperature: return model.temperatureHistory.values
        }
    }

    private var subtitle: String {
        switch metric {
        case .cpu: return Format.percent(model.system.cpuPercent)
        case .memory:
            return "\(Format.bytes(model.system.memoryUsedBytes))/\(Format.bytes(model.system.memoryTotalBytes))"
        case .disk:
            return Format.bytesPerSecond(model.system.diskReadBytesPerSec + model.system.diskWriteBytesPerSec)
        case .network:
            return Format.megabitsPerSecond(model.system.networkInBytesPerSec + model.system.networkOutBytesPerSec)
        case .temperature:
            return model.system.cpuTemperatureCelsius.map(Format.celsius) ?? "—"
        }
    }
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("t", index), y: .value("v", value))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

private struct DetailPane: View {
    @EnvironmentObject var model: TaskManagerViewModel
    let metric: PerformanceMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(metric.rawValue).font(.system(size: 34, weight: .semibold))

            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Seconds", index), y: .value("Value", value))
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Seconds", index), y: .value("Value", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor.opacity(0.15))
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartXAxis(.hidden)
            .frame(minHeight: 260)

            HStack {
                Text("60 seconds").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(yMax))\(yAxisUnit)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            statsGrid
            Spacer()
        }
        .padding(24)
    }

    private var history: [Double] {
        switch metric {
        case .cpu: return model.cpuHistory.values
        case .memory: return model.memoryHistory.values
        case .disk: return model.diskHistory.values
        case .network: return model.networkHistory.values
        case .temperature: return model.temperatureHistory.values
        }
    }

    private var yMax: Double {
        switch metric {
        case .cpu, .memory: return 100
        case .temperature: return 110
        default: return max(history.max() ?? 1, 1)
        }
    }

    private var yAxisUnit: String {
        switch metric {
        case .cpu, .memory: return "%"
        case .temperature: return "°C"
        case .disk, .network: return ""
        }
    }

    @ViewBuilder
    private var statsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            switch metric {
            case .cpu:
                stat("Utilization", Format.percent(model.system.cpuPercent))
                stat("Cores", "\(model.system.cpuPerCore.count)")
                stat("Processes", "\(model.system.processCount)")
                stat("Up time", Format.uptime(model.system.uptime))
            case .memory:
                stat("In use", Format.bytes(model.system.memoryUsedBytes))
                stat("Total", Format.bytes(model.system.memoryTotalBytes))
                stat("% used", Format.percentPrecise(model.totalMemoryPercent))
            case .disk:
                stat("Read", Format.bytesPerSecond(model.system.diskReadBytesPerSec))
                stat("Write", Format.bytesPerSecond(model.system.diskWriteBytesPerSec))
            case .network:
                stat("Send", Format.megabitsPerSecond(model.system.networkOutBytesPerSec))
                stat("Receive", Format.megabitsPerSecond(model.system.networkInBytesPerSec))
            case .temperature:
                stat("CPU", model.system.cpuTemperatureCelsius.map(Format.celsius) ?? "—")
                stat("GPU", model.system.gpuTemperatureCelsius.map(Format.celsius) ?? "—")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
