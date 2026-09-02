import AppKit
import SwiftUI

struct TaskManagerApp: App {
    var body: some Scene {
        WindowGroup("Task Manager") {
            RootView()
        }
        .windowResizability(.contentSize)
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

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--render-icon"), index + 1 < arguments.count {
    NSApplication.shared.setActivationPolicy(.accessory)
    MainActor.assumeIsolated {
        renderIcon(to: arguments[index + 1])
    }
    exit(0)
}

TaskManagerApp.main()
