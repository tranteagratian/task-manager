import AppKit
import SwiftUI
import TaskManagerCore

struct ProcessesView: View {
    @EnvironmentObject var model: TaskManagerViewModel
    @State private var searchText: String = ""

    private var filteredApps: [ProcessGroup] {
        filter(model.appGroups)
    }
    private var filteredBackground: [ProcessGroup] {
        filter(model.backgroundGroups)
    }

    private func filter(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        guard !searchText.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var maxCPU: Double { max((filteredApps + filteredBackground).map(\.cpuPercent).max() ?? 1, 1) }
    private var maxMemory: UInt64 { max((filteredApps + filteredBackground).map(\.memoryBytes).max() ?? 1, 1) }
    private var maxDisk: Double {
        max((filteredApps + filteredBackground).map { $0.diskReadBytesPerSec + $0.diskWriteBytesPerSec }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ColumnHeaderRow()
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(filteredApps) { group in
                            ProcessRowView(group: group, maxCPU: maxCPU, maxMemory: maxMemory, maxDisk: maxDisk)
                            Divider().padding(.leading, 32)
                        }
                    } header: {
                        SectionHeader(title: "Apps", count: filteredApps.count)
                    }
                    Section {
                        ForEach(filteredBackground) { group in
                            ProcessRowView(group: group, maxCPU: maxCPU, maxMemory: maxMemory, maxDisk: maxDisk)
                            Divider().padding(.leading, 32)
                        }
                    } header: {
                        SectionHeader(title: "Background processes", count: filteredBackground.count)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Processes")
                .font(.title2.weight(.semibold))
            Spacer()
            TextField("Type a name or PID…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text("\(title) (\(count))")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ColumnHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: 80, alignment: .trailing)
            Text("Memory").frame(width: 90, alignment: .trailing)
            Text("Disk").frame(width: 90, alignment: .trailing)
            Text("Network").frame(width: 90, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        Divider()
    }
}

private struct ProcessRowView: View {
    let group: ProcessGroup
    let maxCPU: Double
    let maxMemory: UInt64
    let maxDisk: Double

    private var diskRate: Double { group.diskReadBytesPerSec + group.diskWriteBytesPerSec }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(group.members.count > 1 ? "\(group.name) (\(group.members.count))" : group.name)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            metricCell(Format.percent(group.cpuPercent), fraction: group.cpuPercent / maxCPU)
                .frame(width: 80)
            metricCell(Format.bytes(group.memoryBytes), fraction: Double(group.memoryBytes) / Double(maxMemory))
                .frame(width: 90)
            metricCell(Format.bytesPerSecond(diskRate), fraction: diskRate / maxDisk)
                .frame(width: 90)
            metricCell("—", fraction: 0)
                .frame(width: 90)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func metricCell(_ text: String, fraction: Double) -> some View {
        ZStack(alignment: .trailing) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .frame(maxHeight: .infinity, alignment: .trailing)
            }
            Text(text)
                .monospacedDigit()
                .padding(.trailing, 4)
        }
    }

    private var icon: NSImage {
        if let path = group.bundlePath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .unixExecutable)
    }
}
