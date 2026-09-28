// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "IronZapper", platforms: [.macOS("26.0")], products: [
    .library(name: "IronZapperCore", targets: ["IronZapperCore"]),
    .executable(name: "ironzapper-scan", targets: ["IronZapperCLI"])
], targets: [
    .target(name: "IronZapperCore"),
    .executableTarget(name: "IronZapperCLI", dependencies: ["IronZapperCore"]),
    .target(name: "IronZapperPrivileged", dependencies: ["IronZapperCore"], path: "Helper", exclude: ["main.swift"]),
    .testTarget(name: "IronZapperCoreTests", dependencies: ["IronZapperCore", "IronZapperPrivileged"])
])
