// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TaskManagerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TaskManagerCore", targets: ["TaskManagerCore"])
    ],
    targets: [
        .target(name: "TaskManagerCore"),
        .executableTarget(name: "TaskManager", dependencies: ["TaskManagerCore"]),
    ]
)
