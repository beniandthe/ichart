// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "iChart",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "iChart",
            targets: ["iChart"]
        )
    ],
    targets: [
        .target(
            name: "iChart",
            path: "iChart",
            exclude: [
                "App",
                "Features/Editor",
                "Features/Library/LibraryView.swift",
                "Resources",
                "Shared/ChartFontPreset+SwiftUI.swift"
            ]
        ),
        .testTarget(
            name: "iChartTests",
            dependencies: ["iChart"],
            path: "iChartTests",
            exclude: [
                "Fixtures"
            ]
        )
    ]
)
