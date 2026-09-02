import Foundation

/// UserDefaults keys for which metrics the menu bar item shows. Plain
/// @AppStorage-backed booleans — small, flat set of toggles, no need for
/// anything heavier.
enum MenuBarPreferenceKey {
    static let showCPU = "menuBar.showCPU"
    static let showMemory = "menuBar.showMemory"
    static let showDisk = "menuBar.showDisk"
    static let showNetwork = "menuBar.showNetwork"
    static let showTemperature = "menuBar.showTemperature"
}
