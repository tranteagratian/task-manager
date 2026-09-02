import SwiftUI

/// SwiftUI's `openWindow`/`openSettings` environment actions only exist
/// inside views the Scene graph actually hosts. The menu bar's status item
/// and its popover are built by hand with AppKit (see StatusBarController)
/// to work around MenuBarExtra's width bug, which puts them outside that
/// graph — so the one view that *does* have these actions (RootView) hands
/// them here once, for the status bar controller to call later.
@MainActor
final class AppActions: ObservableObject {
    var openMainWindow: OpenWindowAction?
    var openSettingsWindow: OpenSettingsAction?
}
