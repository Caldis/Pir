// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pir",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Pir", targets: ["Pir"])],
    dependencies: [
        .package(path: "Vendor/Vortex"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "PirCore"),
        .executableTarget(name: "Pir", dependencies: ["PirCore", .product(name: "Vortex", package: "Vortex"), .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PirCoreTests", dependencies: ["PirCore"]),
        .testTarget(name: "PirUITests", dependencies: ["Pir", "PirCore"])
    ],
    swiftLanguageModes: [.v5]
)
