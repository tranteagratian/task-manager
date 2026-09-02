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

    func start(interval: TimeInterval = 1.5) {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
}
