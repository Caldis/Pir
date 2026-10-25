// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Puv",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Puv", targets: ["Puv"])],
    dependencies: [
        .package(path: "Vendor/Vortex"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "PuvCore"),
        .executableTarget(name: "Puv", dependencies: ["PuvCore", .product(name: "Vortex", package: "Vortex"), .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PuvCoreTests", dependencies: ["PuvCore"]),
        .testTarget(name: "PuvUITests", dependencies: ["Puv", "PuvCore"])
    ],
    swiftLanguageModes: [.v5]
)
