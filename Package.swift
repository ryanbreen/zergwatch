// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZergWatch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZergWatch", targets: ["ZergWatch"])
    ],
    targets: [
        .executableTarget(
            name: "ZergWatch",
            exclude: [
                "Resources/Info.plist"
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ZergWatch/Resources/Info.plist"
                ])
            ]
        )
    ]
)
