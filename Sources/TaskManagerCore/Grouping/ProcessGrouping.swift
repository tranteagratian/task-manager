import AppKit
import Foundation

/// Folds child/helper processes under their owning app, and separates
/// foreground GUI apps from everything else — the "Apps (3)" /
/// "Background processes (41)" split from Windows 11's Processes tab.
public enum ProcessGrouping {
    public static func group(_ processes: [ProcessSnapshot]) -> (apps: [ProcessGroup], background: [ProcessGroup]) {
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs: [Int32: NSRunningApplication] = [:]
        for app in runningApps where app.activationPolicy == .regular {
            appPIDs[app.processIdentifier] = app
        }

        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.id, $0) })

        // Walk up each process's parent chain to find which (if any) foreground
        // app owns it, so e.g. a Chrome renderer helper folds under "Google Chrome".
        func owningAppPID(for pid: Int32, depth: Int = 0) -> Int32? {
            if appPIDs[pid] != nil { return pid }
            guard depth < 16, let process = byPID[pid], process.parentPid > 1 else { return nil }
            return owningAppPID(for: process.parentPid, depth: depth + 1)
        }

        var membersByOwner: [Int32: [ProcessSnapshot]] = [:]
        var unowned: [ProcessSnapshot] = []

        for process in processes {
            if let owner = owningAppPID(for: process.id) {
                membersByOwner[owner, default: []].append(process)
            } else {
                unowned.append(process)
            }
        }

        let apps: [ProcessGroup] = appPIDs.compactMap { pid, app in
            guard let members = membersByOwner[pid], !members.isEmpty else { return nil }
            let name = app.localizedName ?? members.first?.name ?? "pid \(pid)"
            return ProcessGroup(
                id: pid, name: name,
                bundlePath: app.bundleURL?.path,
                isApp: true, members: members
            )
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
}
