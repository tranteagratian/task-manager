import Foundation
import IOKit

/// Reads temperature sensors via the SMC (System Management Controller) —
/// the same undocumented-but-long-standing technique iStat Menus, TG Pro
/// and the open-source "Stats" app use. Reading (not writing/fan control)
/// needs no root and no privileged helper: it's a plain IOKit user-client
/// connection to the "AppleSMC" service.
///
/// Apple Silicon has no single "the CPU temperature" key — each generation
/// exposes one sensor per core under a different, undocumented key (e.g.
/// "Tp01" on M1/M2, "Tf04" on M3), and the list keeps changing with every
/// chip generation. Rather than hardcode a table that goes stale the day a
/// new chip ships, this scans every key the SMC actually reports and keeps
/// the ones matching the prefixes Apple has used for CPU/GPU core sensors
/// across M1 through M5 ("Tp"/"Te"/"Tf" for CPU cores, "Tg" for GPU cores),
/// filtered to a plausible temperature range so a misread byte can't produce
/// a nonsense number.
public final class SMCTemperature: @unchecked Sendable {
    public static let shared = SMCTemperature()

    private var connection: io_connect_t = 0
    private var cachedKeys: [String]?

    private init() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }
        IOServiceOpen(device, mach_task_self_, 0, &connection)
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func cpuTemperatureCelsius() -> Double? {
        average(prefixes: ["Tp", "Te", "Tf"])
    }

    public func gpuTemperatureCelsius() -> Double? {
        average(prefixes: ["Tg"])
    }

    private func average(prefixes: [String]) -> Double? {
        guard connection != 0 else { return nil }
        let keys = allKeys().filter { key in prefixes.contains { key.hasPrefix($0) } }
        let readings = keys.compactMap(value(for:)).filter { $0 > 0 && $0 < 105 }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    // MARK: - SMC protocol
    //
    // Struct layout mirrors Apple's undocumented SMCKeyData_t exactly (field
    // for field, same nested struct boundaries) rather than approximating it
    // with tuples — IOConnectCallStructMethod reads/writes this by raw byte
    // offset, so a layout that's merely "close" would silently misread every
    // value instead of failing loudly.

    private enum DataType: String {
        case sp78 = "sp78"
        case flt = "flt "
    }

    private enum Selector: UInt8 {
        case kernelIndex = 2
        case readBytes = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct KeyData {
        typealias Bytes32 = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )
        var key: UInt32 = 0
        var vers = Version()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func stringFromCode(_ code: UInt32) -> String {
        let bytes: [UInt8] = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, UInt32(Selector.kernelIndex.rawValue), &input, inputSize, &output, &outputSize)
        return result == kIOReturnSuccess ? output : nil
    }

    private func allKeys() -> [String] {
        if let cachedKeys { return cachedKeys }

        var countInfoInput = KeyData()
        countInfoInput.key = fourCharCode("#KEY")
        countInfoInput.data8 = Selector.readKeyInfo.rawValue
        guard let countInfoOutput = call(&countInfoInput) else { return [] }

        var countReadInput = KeyData()
        countReadInput.key = fourCharCode("#KEY")
        countReadInput.keyInfo.dataSize = countInfoOutput.keyInfo.dataSize
        countReadInput.data8 = Selector.readBytes.rawValue
        guard let countReadOutput = call(&countReadInput) else { return [] }

        let b = countReadOutput.bytes
        let count = Int(UInt32(b.0) << 24 | UInt32(b.1) << 16 | UInt32(b.2) << 8 | UInt32(b.3))
        guard count > 0, count < 10_000 else { return [] }

        var keys: [String] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var input = KeyData()
            input.data8 = Selector.readIndex.rawValue
            input.data32 = UInt32(index)
            guard let output = call(&input) else { continue }
            keys.append(stringFromCode(output.key))
        }
        cachedKeys = keys
        return keys
    }

    private func value(for key: String) -> Double? {
        var infoInput = KeyData()
        infoInput.key = fourCharCode(key)
        infoInput.data8 = Selector.readKeyInfo.rawValue
        guard let infoOutput = call(&infoInput) else { return nil }

        var readInput = KeyData()
        readInput.key = fourCharCode(key)
        readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        readInput.data8 = Selector.readBytes.rawValue
        guard let readOutput = call(&readInput) else { return nil }

        let dataType = stringFromCode(infoOutput.keyInfo.dataType)
        let b = readOutput.bytes

        switch dataType {
        case DataType.sp78.rawValue:
            // Signed 8.8 fixed point: high byte is the integer part.
            let raw = Int16(bitPattern: UInt16(b.0) << 8 | UInt16(b.1))
            return Double(raw) / 256.0
        case DataType.flt.rawValue:
            let bytes: [UInt8] = [b.0, b.1, b.2, b.3]
            let float = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
            return float.isFinite ? Double(float) : nil
        default:
            return nil
        }
    }
}
