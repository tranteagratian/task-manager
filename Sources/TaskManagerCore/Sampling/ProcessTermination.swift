import Darwin

/// Ends processes the same way Activity Monitor's "Quit"/"Force Quit" does:
/// a plain POSIX signal. No privileged helper is needed for processes the
/// current user owns; killing another user's process fails silently (kill
/// returns EPERM), same as it would from Terminal without sudo.
public enum ProcessTermination {
    public static func isAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// Asks the process to quit (SIGTERM) — the well-behaved app gets a
    /// chance to clean up, matching Windows' "End task" on a responsive app.
    public static func requestTermination(pid: Int32) {
        kill(pid, SIGTERM)
    }

    /// Kills the process outright (SIGKILL) — no cleanup, for when
    /// requestTermination didn't work, matching "Force Quit"/an
    /// unresponsive app's "End task".
    public static func forceKill(pid: Int32) {
        kill(pid, SIGKILL)
    }
}
