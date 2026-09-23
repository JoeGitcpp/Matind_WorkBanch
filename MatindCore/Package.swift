// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MatindCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MatindCore", targets: ["MatindCore"])
    ],
    targets: [
        .target(name: "MatindCore"),
        .testTarget(name: "MatindCoreTests", dependencies: ["MatindCore"])
    ]
)
