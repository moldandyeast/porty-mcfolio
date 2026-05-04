// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortyMcFolioDeps",
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: []
)
