import Foundation

enum Format {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value.rounded())
    }

    static func percentPrecise(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func bytesExact(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let grouped = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(grouped) bytes"
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let mb = value / 1_048_576
        if mb < 0.05 { return "0 MB/s" }
        return String(format: "%.1f MB/s", mb)
    }

    static func megabitsPerSecond(_ value: Double) -> String {
        let mbps = value * 8 / 1_000_000
        if mbps < 0.05 { return "0 Mbps" }
        return String(format: "%.1f Mbps", mbps)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return String(format: "%d:%02d:%02d:%02d", days, hours, minutes, secs)
    }
}
