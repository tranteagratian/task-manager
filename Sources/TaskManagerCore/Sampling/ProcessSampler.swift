import Darwin
import Foundation

/// Samples the live process table via libproc. No entitlements are required
/// for reading your own user's processes; other users' processes simply come
/// back with zeroed resource fields, same as Activity Monitor without admin.
public final class ProcessSampler {
    private struct PreviousUsage {
        let cpuTimeTicks: UInt64
        let diskReadBytes: UInt64
        let diskWriteBytes: UInt64
        let timestamp: DispatchTime
    }

    private var previous: [Int32: PreviousUsage] = [:]
    private let coreCount: Double
    /// ri_user_time/ri_system_time are Mach absolute time ticks, not
    /// nanoseconds — on Apple Silicon the timebase is roughly 125/3
    /// (~41.7 ns/tick), so reading them as raw nanoseconds understated CPU
    /// time by ~24x and made everything round down to 0%.
    private let ticksToNanoseconds: Double

    public init() {
        coreCount = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksToNanoseconds = timebase.denom > 0 ? Double(timebase.numer) / Double(timebase.denom) : 1
    }

    public func sample() -> [ProcessSnapshot] {
        let pids = Self.listPIDs()
        let now = DispatchTime.now()
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pids.count)
        var nextPrevious: [Int32: PreviousUsage] = [:]
        nextPrevious.reserveCapacity(pids.count)

        for pid in pids {
            guard let rusage = Self.rusage(for: pid) else { continue }
            let name = Self.name(for: pid) ?? "pid \(pid)"
            let path = Self.path(for: pid)
            let parentPid = Self.parentPID(of: pid)

            let cpuTimeTicks = rusage.ri_user_time &+ rusage.ri_system_time
            let diskRead = rusage.ri_diskio_bytesread
            let diskWrite = rusage.ri_diskio_byteswritten

            var cpuPercent = 0.0
            var readRate = 0.0
            var writeRate = 0.0

            if let prev = previous[pid] {
                let elapsedSeconds = Double(now.uptimeNanoseconds - prev.timestamp.uptimeNanoseconds) / 1_000_000_000
                if elapsedSeconds > 0 {
                    let deltaCPUTicks = cpuTimeTicks >= prev.cpuTimeTicks ? cpuTimeTicks - prev.cpuTimeTicks : 0
                    let deltaCPUNanos = Double(deltaCPUTicks) * ticksToNanoseconds
                    let rawPercent = (deltaCPUNanos / 1_000_000_000) / elapsedSeconds * 100
                    // Normalize to whole-system capacity (Windows Task Manager
                    // behavior) instead of Activity Monitor's per-core sum,
                    // which is what makes 400%+ readings show up there.
                    cpuPercent = min(rawPercent / coreCount, 100)

                    let deltaRead = diskRead >= prev.diskReadBytes ? diskRead - prev.diskReadBytes : 0
                    let deltaWrite = diskWrite >= prev.diskWriteBytes ? diskWrite - prev.diskWriteBytes : 0
                    readRate = Double(deltaRead) / elapsedSeconds
                    writeRate = Double(deltaWrite) / elapsedSeconds
                }
            }

            nextPrevious[pid] = PreviousUsage(
                cpuTimeTicks: cpuTimeTicks, diskReadBytes: diskRead,
                diskWriteBytes: diskWrite, timestamp: now
            )

            results.append(ProcessSnapshot(
                id: pid,
                parentPid: parentPid,
                name: name,
                bundleID: nil,
                bundlePath: path,
                isForegroundApp: false,
                cpuPercent: cpuPercent,
                memoryBytes: rusage.ri_phys_footprint,
                diskReadBytesPerSec: readRate,
                diskWriteBytesPerSec: writeRate
            ))
        }

        previous = nextPrevious
        return results
    }

    // MARK: - libproc bridging

    private static func listPIDs() -> [Int32] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(bufferSize) / MemoryLayout<Int32>.size)
        let actualSize = pids.withUnsafeMutableBytes { ptr in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, ptr.baseAddress, Int32(ptr.count))
        }
        guard actualSize > 0 else { return [] }
        let count = Int(actualSize) / MemoryLayout<Int32>.size
        return Array(pids.prefix(count)).filter { $0 > 0 }
    }

    private static func rusage(for pid: Int32) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &info) { infoPtr -> Int32 in
            infoPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rawPtr)
            }
        }
        return result == 0 ? info : nil
    }

    private static func name(for pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { ptr in
            proc_name(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func path(for pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { ptr in
            proc_pidpath(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func parentPID(of pid: Int32) -> Int32 {
        var info = proc_bsdinfo()
        let size = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { return 0 }
        return Int32(info.pbi_ppid)
    }
}
