import AppKit
import Foundation
import TaskManagerCore

@MainActor
final class TaskManagerViewModel: ObservableObject {
    @Published private(set) var appGroups: [ProcessGroup] = []
    @Published private(set) var backgroundGroups: [ProcessGroup] = []
    @Published private(set) var system: SystemSnapshot = .zero

    @Published private(set) var cpuHistory = RollingSeries()
    @Published private(set) var memoryHistory = RollingSeries()
    @Published private(set) var diskHistory = RollingSeries()
    @Published private(set) var networkHistory = RollingSeries()

    private let processSampler = ProcessSampler()
    private let systemSampler = SystemSampler()
    private var timer: Timer?
    private var hasStarted = false

    func start(interval: TimeInterval = 1.5) {
        guard !hasStarted else { return }
        hasStarted = true

        // The samplers compute CPU/disk/network as deltas between two calls,
        // so the very first sample has nothing to diff against and reads as
        // zero. Warm them up with a throwaway call before the first reading
        // that actually gets recorded, so the charts don't open with a false
        // zero baseline.
        _ = processSampler.sample()
        _ = systemSampler.sample()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            self.refresh()
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hasStarted = false
    }

    private func refresh() {
        let processes = processSampler.sample()
        let grouped = ProcessGrouping.group(processes)
        appGroups = grouped.apps
        backgroundGroups = grouped.background

        let snapshot = systemSampler.sample()
        system = snapshot

        cpuHistory.append(snapshot.cpuPercent)
        let memoryPercent = snapshot.memoryTotalBytes > 0
            ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100 : 0
        memoryHistory.append(memoryPercent)
        diskHistory.append(snapshot.diskReadBytesPerSec + snapshot.diskWriteBytesPerSec)
        networkHistory.append(snapshot.networkInBytesPerSec + snapshot.networkOutBytesPerSec)
    }

    var totalCPUPercent: Double { system.cpuPercent }
    var totalMemoryPercent: Double {
        system.memoryTotalBytes > 0 ? Double(system.memoryUsedBytes) / Double(system.memoryTotalBytes) * 100 : 0
    }

    // MARK: - Ending tasks

    func endTask(_ group: ProcessGroup) {
        guard !group.isProtected else { return }
        for member in group.members {
            ProcessTermination.requestTermination(pid: member.id)
        }
    }

    func forceEndTask(_ group: ProcessGroup) {
        guard !group.isProtected else { return }
        for member in group.members {
            ProcessTermination.forceKill(pid: member.id)
        }
    }

    func isStillRunning(_ group: ProcessGroup) -> Bool {
        group.members.contains { ProcessTermination.isAlive(pid: $0.id) }
    }

    // MARK: - Restart

    func canRestart(_ group: ProcessGroup) -> Bool {
        group.isApp && !group.isProtected && group.bundlePath?.hasSuffix(".app") == true
    }

    func restart(_ group: ProcessGroup) {
        guard canRestart(group), let bundlePath = group.bundlePath else { return }
        let url = URL(fileURLWithPath: bundlePath)
        for member in group.members {
            ProcessTermination.requestTermination(pid: member.id)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
    }

    // MARK: - Efficiency mode

    func isEfficiencyMode(_ group: ProcessGroup) -> Bool {
        group.members.allSatisfy { ProcessPriority.isEfficiencyMode(pid: $0.id) }
    }

    func setEfficiencyMode(_ group: ProcessGroup, enabled: Bool) {
        guard !group.isProtected else { return }
        for member in group.members {
            ProcessPriority.setEfficiencyMode(pid: member.id, enabled: enabled)
        }
    }
}
