// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TX500Utility",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TX500Kit", targets: ["TX500Kit"]),
        .executable(name: "TX500Utility", targets: ["TX500Utility"]),
        .executable(name: "tx500", targets: ["tx500cli"]),
    ],
    targets: [
        .target(name: "TX500Kit"),
        .executableTarget(name: "TX500Utility", dependencies: ["TX500Kit"], resources: [.process("Resources")]),
        .executableTarget(name: "tx500cli", dependencies: ["TX500Kit"]),
        .testTarget(name: "TX500KitTests", dependencies: ["TX500Kit"], resources: [.copy("Fixtures")]),
    ]
)
