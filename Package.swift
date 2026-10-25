// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Puv",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Puv", targets: ["Puv"])],
    dependencies: [
        .package(path: "Vendor/PermissionFlow")
    ],
    targets: [
        .target(name: "PuvCore"),
        .executableTarget(name: "Puv", dependencies: ["PuvCore", .product(name: "PermissionFlow", package: "PermissionFlow")], resources: [.process("Resources")]),
        .testTarget(name: "PuvCoreTests", dependencies: ["PuvCore"]),
        .testTarget(name: "PuvUITests", dependencies: ["Puv", "PuvCore"])
    ],
    swiftLanguageModes: [.v5]
)
