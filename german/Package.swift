// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GermanPractice",
    platforms: [.macOS(.v26)],
    products: [.library(name: "GermanPractice", targets: ["GermanPractice"])],
    targets: [
        .target(name: "GermanPractice", path: "german",
                exclude: ["ContentView.swift", "germanApp.swift", "Assets.xcassets", "Canvas", "Sentences", "Settings", "german.entitlements"],
                sources: ["Practice", "Services"],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "GermanPracticeTests", dependencies: ["GermanPractice"], path: "Tests/GermanPracticeTests")
    ],
    swiftLanguageModes: [.v5]
)
