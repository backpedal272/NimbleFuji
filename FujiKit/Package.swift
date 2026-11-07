// swift-tools-version: 6.2
//
// FujiKit — native Swift control of Fujifilm cameras over USB PTP.
// A Swift port of fujicli's fujicore (https://github.com/karaolidis/fujicli).
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import PackageDescription

let package = Package(
    name: "FujiKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FujiKit", targets: ["FujiKit"]),
        .executable(name: "fujikit", targets: ["fujikit"]),
    ],
    targets: [
        .target(
            name: "FujiKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
            ]
        ),
        .executableTarget(name: "fujikit", dependencies: ["FujiKit"], path: "Sources/FujiKitCLI"),
        .testTarget(name: "FujiKitTests", dependencies: ["FujiKit"], resources: [.copy("Fixtures")]),
    ]
)
