import AppKit
import Foundation

/// Folds child/helper processes under their owning app, and separates
/// foreground GUI apps from everything else — the "Apps (3)" /
/// "Background processes (41)" split from Windows 11's Processes tab.
public enum ProcessGrouping {
    public static func group(_ processes: [ProcessSnapshot]) -> (apps: [ProcessGroup], background: [ProcessGroup]) {
        let runningApps = NSWorkspace.shared.runningApplications
        var appsByBundlePath: [String: NSRunningApplication] = [:]
        for app in runningApps {
            if let path = app.bundleURL?.path {
                appsByBundlePath[path] = app
            }
        }
        var regularAppPIDs: Set<Int32> = []
        for app in runningApps where app.activationPolicy == .regular {
            regularAppPIDs.insert(app.processIdentifier)
        }

        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.id, $0) })

        // Fallback for the rare process that doesn't live inside a .app
        // bundle at all (a bare Unix helper): walk up its parent chain to
        // see whether a regular foreground app spawned it directly.
        func parentOwningAppPID(for pid: Int32, depth: Int = 0) -> Int32? {
            if regularAppPIDs.contains(pid) { return pid }
            guard depth < 16, let process = byPID[pid], process.parentPid > 1 else { return nil }
            return parentOwningAppPID(for: process.parentPid, depth: depth + 1)
        }

        var membersByBundlePath: [String: [ProcessSnapshot]] = [:]
        var membersByParentPID: [Int32: [ProcessSnapshot]] = [:]
        var unowned: [ProcessSnapshot] = []

        for process in processes {
            // Primary signal: the process's own executable path. A VM engine
            // or helper spawned via launchd/XPC (not a direct fork of the
            // app) has no parent-PID link back to its app, but it still runs
            // from *inside* that app's .app bundle — e.g. Parallels'
            // prl_vm_app lives under "Parallels Desktop.app/Contents/...".
            // Matching on the bundle path catches those the parent walk
            // misses entirely.
            if let outerPath = outerAppBundlePath(from: process.bundlePath) {
                let owningApp = appsByBundlePath[outerPath]
                if owningApp == nil || owningApp?.activationPolicy == .regular {
                    membersByBundlePath[outerPath, default: []].append(process)
                    continue
                }
            }
            if let owner = parentOwningAppPID(for: process.id) {
                membersByParentPID[owner, default: []].append(process)
            } else {
                unowned.append(process)
            }
        }

        var apps: [ProcessGroup] = membersByBundlePath.compactMap { path, members in
            guard !members.isEmpty else { return nil }
            let app = appsByBundlePath[path]
            let name = app?.localizedName ?? bundleDisplayName(for: path)
            let representativePID = app?.processIdentifier ?? members[0].id
            return ProcessGroup(id: representativePID, name: name, bundlePath: path, isApp: true, members: members)
        }

        apps += membersByParentPID.compactMap { pid, members in
            guard !members.isEmpty else { return nil }
            let app = runningApps.first { $0.processIdentifier == pid }
            let name = app?.localizedName ?? members.first?.name ?? "pid \(pid)"
            return ProcessGroup(id: pid, name: name, bundlePath: app?.bundleURL?.path, isApp: true, members: members)
        }

        let background: [ProcessGroup] = unowned.map { process in
            ProcessGroup(
                id: process.id, name: process.name,
                bundlePath: process.bundlePath,
                isApp: false, members: [process]
            )
        }

        return (apps.sorted { $0.name < $1.name }, background.sorted { $0.name < $1.name })
    }

    /// The path through the outermost ".app" directory in an executable's
    /// path, e.g. ".../Parallels Desktop.app/Contents/MacOS//Parallels
    /// VM.app/Contents/MacOS/prl_vm_app" -> ".../Parallels Desktop.app".
    /// Stopping at the *first* match is what folds a nested helper bundle
    /// into its containing app rather than treating it as its own app.
    private static func outerAppBundlePath(from executablePath: String?) -> String? {
        guard let path = executablePath, let range = path.range(of: ".app/") else { return nil }
        let throughTrailingSlash = path[path.startIndex..<range.upperBound]
        return String(throughTrailingSlash.dropLast())
    }

    private static func bundleDisplayName(for bundlePath: String) -> String {
        (bundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
}
