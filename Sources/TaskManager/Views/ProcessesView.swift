import AppKit
import SwiftUI
import TaskManagerCore

enum ProcessSortKey: String {
    case name, cpu, memory, disk
}

struct ProcessesView: View {
    @EnvironmentObject var model: TaskManagerViewModel
    @State private var searchText: String = ""
    @State private var sortKey: ProcessSortKey = .name
    @State private var sortAscending: Bool = true

    private var filteredApps: [ProcessGroup] {
        sort(filter(model.appGroups))
    }
    private var filteredBackground: [ProcessGroup] {
        sort(filter(model.backgroundGroups))
    }

    private func filter(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        guard !searchText.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func sort(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        let sorted: [ProcessGroup]
        switch sortKey {
        case .name:
            sorted = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .cpu:
            sorted = groups.sorted { $0.cpuPercent < $1.cpuPercent }
        case .memory:
            sorted = groups.sorted { $0.memoryBytes < $1.memoryBytes }
        case .disk:
            sorted = groups.sorted { ($0.diskReadBytesPerSec + $0.diskWriteBytesPerSec) < ($1.diskReadBytesPerSec + $1.diskWriteBytesPerSec) }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    private func toggleSort(_ key: ProcessSortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = key == .name
        }
    }

    private var maxCPU: Double { max((filteredApps + filteredBackground).map(\.cpuPercent).max() ?? 1, 1) }
    private var maxMemory: UInt64 { max((filteredApps + filteredBackground).map(\.memoryBytes).max() ?? 1, 1) }
    private var maxDisk: Double {
        max((filteredApps + filteredBackground).map { $0.diskReadBytesPerSec + $0.diskWriteBytesPerSec }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ColumnHeaderRow(sortKey: sortKey, sortAscending: sortAscending, onSelect: toggleSort)
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
    let sortKey: ProcessSortKey
    let sortAscending: Bool
    let onSelect: (ProcessSortKey) -> Void

    var body: some View {
        HStack(spacing: 0) {
            headerButton("Name", key: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton("CPU", key: .cpu, alignment: .trailing)
                .frame(width: 80, alignment: .trailing)
            headerButton("Memory", key: .memory, alignment: .trailing)
                .frame(width: 90, alignment: .trailing)
            headerButton("Disk", key: .disk, alignment: .trailing)
                .frame(width: 90, alignment: .trailing)
            Text("Network").frame(width: 90, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        Divider()
    }

    private func headerButton(_ title: String, key: ProcessSortKey, alignment: Alignment) -> some View {
        Button { onSelect(key) } label: {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title)
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
