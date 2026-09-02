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
}
