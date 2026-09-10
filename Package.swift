// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sirius",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Sirius",
            targets: ["Sirius"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Sirius",
            dependencies: [],
            path: "Sources/Sirius",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
