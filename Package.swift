// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NextCursor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NextCursor", targets: ["NextCursor"])
    ],
    targets: [
        .executableTarget(
            name: "NextCursor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("JavaRuntimeSupport")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
