import AppKit
import SwiftUI
import TaskManagerCore

enum ProcessSortKey: String {
    case name, cpu, memory, disk
}

private struct SelectionKey: Hashable {
    let isApp: Bool
    let id: Int32
}

struct ProcessesView: View {
    @EnvironmentObject var model: TaskManagerViewModel
    @State private var searchText: String = ""
    @State private var sortKey: ProcessSortKey = .cpu
    @State private var sortAscending: Bool = false
    @State private var selection: SelectionKey?
    @State private var expandedKeys: Set<SelectionKey> = []
    @State private var pendingEndTask: ProcessGroup?
    @State private var pendingForceQuit: ProcessGroup?
    @State private var pendingRestart: ProcessGroup?

    private var filteredApps: [ProcessGroup] {
        sort(filter(model.appGroups))
    }
    private var filteredBackground: [ProcessGroup] {
        sort(filter(model.backgroundGroups))
    }

    private var selectedGroup: ProcessGroup? {
        guard let selection else { return nil }
        let pool = selection.isApp ? filteredApps : filteredBackground
        return pool.first { $0.id == selection.id }
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
                            row(for: group, isApp: true)
                        }
                    } header: {
                        SectionHeader(title: "Apps", count: filteredApps.count)
                    }
                    Section {
                        ForEach(filteredBackground) { group in
                            row(for: group, isApp: false)
                        }
                    } header: {
                        SectionHeader(title: "Background processes", count: filteredBackground.count)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("End \(pendingEndTask?.name ?? "")?", isPresented: Binding(
            get: { pendingEndTask != nil }, set: { if !$0 { pendingEndTask = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingEndTask = nil }
            Button("End Task", role: .destructive) {
                guard let group = pendingEndTask else { return }
                model.endTask(group)
                pendingEndTask = nil
                scheduleForceQuitCheck(for: group)
            }
        } message: {
            Text("This immediately closes the app and any unsaved work in it will be lost.")
        }
        .alert("\(pendingForceQuit?.name ?? "") isn't responding", isPresented: Binding(
            get: { pendingForceQuit != nil }, set: { if !$0 { pendingForceQuit = nil } }
        )) {
            Button("Wait") { pendingForceQuit = nil }
            Button("Force Quit", role: .destructive) {
                guard let group = pendingForceQuit else { return }
                model.forceEndTask(group)
                pendingForceQuit = nil
            }
        } message: {
            Text("It didn't quit on its own. Force quitting skips its normal cleanup.")
        }
        .alert("Restart \(pendingRestart?.name ?? "")?", isPresented: Binding(
            get: { pendingRestart != nil }, set: { if !$0 { pendingRestart = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingRestart = nil }
            Button("Restart") {
                guard let group = pendingRestart else { return }
                model.restart(group)
                pendingRestart = nil
            }
        } message: {
            Text("This quits the app and reopens it. Any unsaved work in it will be lost.")
        }
    }

    private func row(for group: ProcessGroup, isApp: Bool) -> some View {
        let key = SelectionKey(isApp: isApp, id: group.id)
        let isExpanded = expandedKeys.contains(key)
        return VStack(spacing: 0) {
            ProcessRowView(
                group: group, maxCPU: maxCPU, maxMemory: maxMemory, maxDisk: maxDisk,
                isSelected: selection == key, isExpanded: isExpanded,
                onToggleExpand: group.members.count > 1 ? {
                    if isExpanded { expandedKeys.remove(key) } else { expandedKeys.insert(key) }
                } : nil
            )
            .contentShape(Rectangle())
            .onTapGesture { selection = key }
            .contextMenu { contextMenu(for: group) }
            Divider().padding(.leading, 32)

            if isExpanded {
                ForEach(group.members.sorted(by: { $0.cpuPercent > $1.cpuPercent })) { member in
                    MemberRowView(member: member, maxCPU: maxCPU, maxMemory: maxMemory, maxDisk: maxDisk)
                    Divider().padding(.leading, 48)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for group: ProcessGroup) -> some View {
        if group.members.count > 1 {
            Button(expandedKeys.contains(SelectionKey(isApp: group.isApp, id: group.id)) ? "Collapse" : "Expand") {
                let key = SelectionKey(isApp: group.isApp, id: group.id)
                if expandedKeys.contains(key) { expandedKeys.remove(key) } else { expandedKeys.insert(key) }
            }
        }
        if model.canRestart(group) {
            Button("Restart") { pendingRestart = group }
        }
        Menu("Resource values") {
            Text("CPU: \(Format.percentPrecise(group.cpuPercent))")
            Text("Memory: \(Format.bytesExact(group.memoryBytes))")
            Text("Disk: \(Format.bytesPerSecond(group.diskReadBytesPerSec + group.diskWriteBytesPerSec))")
        }
        Divider()
        Toggle("Efficiency Mode", isOn: Binding(
            get: { model.isEfficiencyMode(group) },
            set: { model.setEfficiencyMode(group, enabled: $0) }
        ))
        .disabled(group.isProtected)
        Divider()
        if let bundlePath = group.bundlePath {
            Button("Open File Location") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bundlePath)])
            }
        }
        Button("Search Online") {
            let query = group.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? group.name
            if let url = URL(string: "https://www.google.com/search?q=\(query)") {
                NSWorkspace.shared.open(url)
            }
        }
        Divider()
        Button("End Task") { pendingEndTask = group }
            .disabled(group.isProtected)
    }

    private func scheduleForceQuitCheck(for group: ProcessGroup) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if model.isStillRunning(group) {
                pendingForceQuit = group
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Processes")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                if let group = selectedGroup { pendingEndTask = group }
            } label: {
                Label("End Task", systemImage: "xmark.circle")
            }
            .disabled(selectedGroup == nil || selectedGroup?.isProtected == true)
            .help(selectedGroup?.isProtected == true ? "This is a critical system process and can't be ended here." : "")
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
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?

    private var diskRate: Double { group.diskReadBytesPerSec + group.diskWriteBytesPerSec }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Group {
                    if let onToggleExpand {
                        Button(action: onToggleExpand) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 12)

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
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear)
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

/// One member of an expanded group — its own PID's numbers, indented under
/// the group row, no icon of its own (it belongs to the app above it).
private struct MemberRowView: View {
    let member: ProcessSnapshot
    let maxCPU: Double
    let maxMemory: UInt64
    let maxDisk: Double

    private var diskRate: Double { member.diskReadBytesPerSec + member.diskWriteBytesPerSec }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(member.name)  ·  pid \(member.id)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 32)

            metricCell(Format.percent(member.cpuPercent), fraction: member.cpuPercent / maxCPU)
                .frame(width: 80)
            metricCell(Format.bytes(member.memoryBytes), fraction: Double(member.memoryBytes) / Double(maxMemory))
                .frame(width: 90)
            metricCell(Format.bytesPerSecond(diskRate), fraction: diskRate / maxDisk)
                .frame(width: 90)
            metricCell("—", fraction: 0)
                .frame(width: 90)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func metricCell(_ text: String, fraction: Double) -> some View {
        ZStack(alignment: .trailing) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .frame(maxHeight: .infinity, alignment: .trailing)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.trailing, 4)
        }
    }
}
