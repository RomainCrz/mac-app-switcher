// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacAppSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacAppSwitcher", targets: ["MacAppSwitcher"])
    ],
    targets: [
        .executableTarget(name: "MacAppSwitcher")
    ]
)
