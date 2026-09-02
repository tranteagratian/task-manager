import Darwin

/// The closest real equivalent to Windows' Efficiency Mode: lowering a
/// process's scheduling priority (nice value) so the OS favors everything
/// else over it. Lowering your own process's priority needs no privilege;
/// only raising it above default does, which this never does.
public enum ProcessPriority {
    public static let efficiencyNiceValue: Int32 = 20
    private static let defaultNiceValue: Int32 = 0

    @discardableResult
    public static func setEfficiencyMode(pid: Int32, enabled: Bool) -> Bool {
        setpriority(PRIO_PROCESS, UInt32(pid), enabled ? efficiencyNiceValue : defaultNiceValue) == 0
    }

    public static func isEfficiencyMode(pid: Int32) -> Bool {
        errno = 0
        let value = getpriority(PRIO_PROCESS, UInt32(pid))
        return errno == 0 && value >= efficiencyNiceValue
    }
}
