import AppKit
import SwiftUI
import TaskManagerCore

struct TaskManagerApp: App {
    @StateObject private var model = TaskManagerViewModel()

    var body: some Scene {
        WindowGroup("Task Manager", id: "main") {
            RootView()
                .environmentObject(model)
                .task { model.start() }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabelView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
func renderIcon(to path: String) {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        print("could not render icon")
        exit(1)
    }
    try? png.write(to: URL(filePath: path))
    print("wrote \(path)")
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
if let index = arguments.firstIndex(of: "--render-icon"), index + 1 < arguments.count {
    NSApplication.shared.setActivationPolicy(.accessory)
    MainActor.assumeIsolated {
        renderIcon(to: arguments[index + 1])
    }
    exit(0)
}

if arguments.contains("--dump-groups") {
    dumpGroups()
    exit(0)
}

TaskManagerApp.main()
