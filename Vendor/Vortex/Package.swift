// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vortex",
    platforms: [.macOS(.v12)],
    products: [.library(name: "Vortex", targets: ["Vortex"])],
    targets: [.target(name: "Vortex", resources: [.process("Resources/Assets.xcassets")])]
)
