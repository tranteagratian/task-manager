import SwiftUI

struct TaskManagerApp: App {
    var body: some Scene {
        WindowGroup("Task Manager") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}

TaskManagerApp.main()
