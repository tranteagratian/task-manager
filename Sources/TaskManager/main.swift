import AppKit
import SwiftUI
import TaskManagerCore

struct TaskManagerApp: App {
    @StateObject private var model = TaskManagerViewModel()
    @StateObject private var actions = AppActions()
    @State private var statusBarController: StatusBarController?

    var body: some Scene {
        WindowGroup("Task Manager", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(actions)
                .task {
                    model.start()
                    if statusBarController == nil {
                        statusBarController = StatusBarController(model: model, actions: actions)
                    }
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

func dumpGroups() {
    let processSampler = ProcessSampler()
    _ = processSampler.sample()
    Thread.sleep(forTimeInterval: 1.5)
    let processes = processSampler.sample()
    let (apps, background) = ProcessGrouping.group(processes)
    print("=== Apps (\(apps.count)) ===")
    for group in apps.sorted(by: { $0.cpuPercent > $1.cpuPercent }) {
        let pct = String(format: "%5.1f%%", group.cpuPercent)
        let memberNames = group.members.map(\.name).joined(separator: ", ")
        print("\(pct)  \(group.name)  members=\(group.members.count) [\(memberNames)]")
    }
    print("=== Background (\(background.count)) ===")
    for group in background.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(10) {
        let pct = String(format: "%5.1f%%", group.cpuPercent)
        print("\(pct)  \(group.name)")
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--dump-groups") {
    dumpGroups()
    exit(0)
}

if arguments.contains("--dump-temps") {
    print("CPU:", SMCTemperature.shared.cpuTemperatureCelsius() as Any)
    print("GPU:", SMCTemperature.shared.gpuTemperatureCelsius() as Any)
    exit(0)
}

TaskManagerApp.main()
