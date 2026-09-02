import Darwin
import Foundation
import IOKit

/// Samples system-wide CPU, memory, disk and network throughput. All of this
/// is readable without root, unlike per-process network traffic (which needs
/// a privileged helper and is deliberately out of scope for now).
public final class SystemSampler {
    private var previousCPUTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var previousDiskBytes: (read: UInt64, write: UInt64)?
    private var previousNetBytes: (in: UInt64, out: UInt64)?
    private var previousTimestamp: DispatchTime?

    public init() {}

    public func sample() -> SystemSnapshot {
        let now = DispatchTime.now()
        let elapsed = previousTimestamp.map { Double(now.uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000_000 } ?? 0
        previousTimestamp = now

        let (overallCPU, perCoreCPU) = sampleCPU()
        let (used, total) = sampleMemory()
        let (diskRead, diskWrite) = sampleDisk(elapsed: elapsed)
        let (netIn, netOut) = sampleNetwork(elapsed: elapsed)

        return SystemSnapshot(
            cpuPercent: overallCPU,
            cpuPerCore: perCoreCPU,
            memoryUsedBytes: used,
            memoryTotalBytes: total,
            diskReadBytesPerSec: diskRead,
            diskWriteBytesPerSec: diskWrite,
            networkInBytesPerSec: netIn,
            networkOutBytesPerSec: netOut,
            processCount: Self.processCount(),
            threadCount: Self.threadCount(),
            uptime: Self.uptime()
        )
    }

    // MARK: - CPU

    private func sampleCPU() -> (overall: Double, perCore: [Double]) {
        var cpuLoadInfo: processor_info_array_t!
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs,
            &cpuLoadInfo, &numCPUInfo
        )
        guard result == KERN_SUCCESS else { return (0, []) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuLoadInfo), vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.size))
        }

        var currentTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            let user = cpuLoadInfo[base + Int(CPU_STATE_USER)]
            let system = cpuLoadInfo[base + Int(CPU_STATE_SYSTEM)]
            let idle = cpuLoadInfo[base + Int(CPU_STATE_IDLE)]
            let nice = cpuLoadInfo[base + Int(CPU_STATE_NICE)]
            currentTicks.append((UInt32(user), UInt32(system), UInt32(idle), UInt32(nice)))
        }

        defer { previousCPUTicks = currentTicks }
        guard previousCPUTicks.count == currentTicks.count, !previousCPUTicks.isEmpty else {
            return (0, Array(repeating: 0, count: currentTicks.count))
        }

        var perCore: [Double] = []
        var totalBusy: Double = 0
        var totalTicks: Double = 0
        for i in 0..<currentTicks.count {
            let prev = previousCPUTicks[i]
            let curr = currentTicks[i]
            let deltaUser = Double(curr.user &- prev.user)
            let deltaSystem = Double(curr.system &- prev.system)
            let deltaIdle = Double(curr.idle &- prev.idle)
            let deltaNice = Double(curr.nice &- prev.nice)
            let busy = deltaUser + deltaSystem + deltaNice
            let total = busy + deltaIdle
            perCore.append(total > 0 ? (busy / total * 100) : 0)
            totalBusy += busy
            totalTicks += total
        }
        let overall = totalTicks > 0 ? (totalBusy / totalTicks * 100) : 0
        return (overall, perCore)
    }

    // MARK: - Memory

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, ProcessInfo.processInfo.physicalMemory) }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        return (min(used, total), total)
    }

    // MARK: - Disk (aggregate, via IOKit block storage statistics)

    private func sampleDisk(elapsed: Double) -> (read: Double, write: Double) {
        let (read, write) = Self.currentDiskBytes()
        defer { previousDiskBytes = (read, write) }
        guard let prev = previousDiskBytes, elapsed > 0 else { return (0, 0) }
        let deltaRead = read >= prev.read ? read - prev.read : 0
        let deltaWrite = write >= prev.write ? write - prev.write : 0
        return (Double(deltaRead) / elapsed, Double(deltaWrite) / elapsed)
    }

    private static func currentDiskBytes() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else { continue }
            if let bytesRead = stats["Bytes (Read)"] as? UInt64 { totalRead += bytesRead }
            if let bytesWrite = stats["Bytes (Write)"] as? UInt64 { totalWrite += bytesWrite }
        }
        return (totalRead, totalWrite)
    }

    // MARK: - Network (aggregate, via interface byte counters)

    private func sampleNetwork(elapsed: Double) -> (in: Double, out: Double) {
        let (inBytes, outBytes) = Self.currentNetworkBytes()
        defer { previousNetBytes = (inBytes, outBytes) }
        guard let prev = previousNetBytes, elapsed > 0 else { return (0, 0) }
        let deltaIn = inBytes >= prev.in ? inBytes - prev.in : 0
        let deltaOut = outBytes >= prev.out ? outBytes - prev.out : 0
        return (Double(deltaIn) / elapsed, Double(deltaOut) / elapsed)
    }

    private static func currentNetworkBytes() -> (in: UInt64, out: UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = current.pointee.ifa_data else { continue }
            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            totalIn += UInt64(networkData.ifi_ibytes)
            totalOut += UInt64(networkData.ifi_obytes)
        }
        return (totalIn, totalOut)
    }

    // MARK: - Misc

    private static func processCount() -> Int {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        return size > 0 ? Int(size) / MemoryLayout<Int32>.size : 0
    }

    private static func threadCount() -> Int {
        // System-wide thread totals aren't exposed via a simple public API;
        // left as a future per-process sum if the Details tab needs it.
        0
    }

    private static func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
