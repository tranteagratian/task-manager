import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item directly via AppKit instead of SwiftUI's
/// MenuBarExtra scene. MenuBarExtra's `.window` style has a real,
/// widely-reported bug: the NSStatusItem's width gets fixed from an early
/// render (often while values are still 0 or nil) and never grows again as
/// content changes — so a label that's supposed to show five metrics can
/// get stuck showing one. Managing the NSStatusItem's length ourselves,
/// keyed off the hosting view's actual fitting size, is the reliable fix
/// production menu bar apps use.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let hostingView: NSHostingView<MenuBarLabelView>
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init(model: TaskManagerViewModel, actions: AppActions) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        hostingView = NSHostingView(rootView: MenuBarLabelView(model: model))

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                model: model,
                onOpenMainWindow: {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    actions.openMainWindow?(id: "main")
                },
                onOpenSettings: {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    actions.openSettingsWindow?()
                }
            )
        )

        super.init()

        if let button = statusItem.button {
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.target = self
            button.action = #selector(handleClick)
        }

        resizeToFitContent()
        // objectWillChange fires just before the mutation lands, so give
        // SwiftUI a run loop turn to actually re-layout the hosting view
        // before measuring it.
        cancellable = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeToFitContent() }
        }
    }

    private func resizeToFitContent() {
        let width = hostingView.fittingSize.width
        statusItem.length = max(width, 20)
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
