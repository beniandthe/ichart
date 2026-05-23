// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SmartChart",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SmartChart",
            targets: ["SmartChart"]
        )
    ],
    targets: [
        .target(
            name: "SmartChart",
            path: "SmartChart",
            exclude: [
                "App",
                "Features/Editor",
                "Features/Library/LibraryView.swift",
                "Resources",
                "Shared/ChartFontPreset+SwiftUI.swift"
            ]
        ),
        .testTarget(
            name: "SmartChartTests",
            dependencies: ["SmartChart"],
            path: "SmartChartTests",
            exclude: [
                "Fixtures"
            ]
        )
    ]
)
