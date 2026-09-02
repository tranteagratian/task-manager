import Foundation

public struct SystemSnapshot: Sendable {
    public var cpuPercent: Double
    public var cpuPerCore: [Double]
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var diskReadBytesPerSec: Double
    public var diskWriteBytesPerSec: Double
    public var networkInBytesPerSec: Double
    public var networkOutBytesPerSec: Double
    public var processCount: Int
    public var threadCount: Int
    public var uptime: TimeInterval

    public static let zero = SystemSnapshot(
        cpuPercent: 0, cpuPerCore: [], memoryUsedBytes: 0, memoryTotalBytes: 0,
        diskReadBytesPerSec: 0, diskWriteBytesPerSec: 0,
        networkInBytesPerSec: 0, networkOutBytesPerSec: 0,
        processCount: 0, threadCount: 0, uptime: 0
    )
}

/// A fixed-length rolling window of samples for the live charts, matching the
/// "60 seconds" sliding graph on the Windows Performance tab.
public struct RollingSeries: Sendable {
    public let capacity: Int
    public private(set) var values: [Double]
    private var hasReceivedSample = false

    public init(capacity: Int = 60) {
        self.capacity = capacity
        self.values = Array(repeating: 0, count: capacity)
    }

    public mutating func append(_ value: Double) {
        // Seed the whole buffer with the first real reading instead of
        // ramping up from zero, so the chart starts flat at the true level.
        if !hasReceivedSample {
            values = Array(repeating: value, count: capacity)
            hasReceivedSample = true
            return
        }
        values.removeFirst()
        values.append(value)
    }
}
