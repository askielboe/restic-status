// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ResticStatus",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "ResticStatus", targets: ["ResticStatus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ResticStatus",
            dependencies: ["Yams"],
            path: "ResticStatus"
        ),
    ]
)
