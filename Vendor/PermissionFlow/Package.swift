// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PermissionFlow",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PermissionFlow", targets: ["PermissionFlow"])],
    targets: [
        .target(name: "SystemSettingsKit"),
        .target(name: "PermissionFlow", dependencies: ["SystemSettingsKit"], resources: [.process("Resources")])
    ]
)
