import Foundation

public struct ProcessSnapshot: Identifiable, Hashable, Sendable {
    public let id: Int32 // pid
    public let parentPid: Int32
    public let name: String
    public let bundleID: String?
    public let bundlePath: String?
    public let isForegroundApp: Bool

    /// Normalized to the whole system (0...100), matching Windows Task Manager
    /// rather than Activity Monitor's per-core sum (which can exceed 100%).
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var diskReadBytesPerSec: Double
    public var diskWriteBytesPerSec: Double

    public init(
        id: Int32, parentPid: Int32, name: String, bundleID: String?, bundlePath: String?,
        isForegroundApp: Bool, cpuPercent: Double, memoryBytes: UInt64,
        diskReadBytesPerSec: Double, diskWriteBytesPerSec: Double
    ) {
        self.id = id
        self.parentPid = parentPid
        self.name = name
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.isForegroundApp = isForegroundApp
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
    }
}

/// A row in the Processes table: either a single process or an app with its
/// helper/child processes folded underneath it, mirroring how Windows 11
/// groups "Google Chrome (23)" into one expandable row.
public struct ProcessGroup: Identifiable, Hashable, Sendable {
    public let id: Int32 // representative pid (the app or the lone process)
    public let name: String
    public let bundlePath: String?
    public let isApp: Bool
    public var members: [ProcessSnapshot]

    public var cpuPercent: Double { members.reduce(0) { $0 + $1.cpuPercent } }
    public var memoryBytes: UInt64 { members.reduce(0) { $0 + $1.memoryBytes } }
    public var diskReadBytesPerSec: Double { members.reduce(0) { $0 + $1.diskReadBytesPerSec } }
    public var diskWriteBytesPerSec: Double { members.reduce(0) { $0 + $1.diskWriteBytesPerSec } }

    /// Processes whose death takes the whole session down with them —
    /// ending them isn't "close an app", it's an instant logout or crash.
    /// Windows Task Manager similarly refuses to end critical system
    /// processes rather than let a misclick black-screen the machine.
    private static let protectedNames: Set<String> = ["loginwindow", "WindowServer", "launchd", "kernel_task"]

    public var isProtected: Bool {
        members.contains { $0.id <= 1 || Self.protectedNames.contains($0.name) }
    }

    public init(id: Int32, name: String, bundlePath: String?, isApp: Bool, members: [ProcessSnapshot]) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.isApp = isApp
        self.members = members
    }
}
