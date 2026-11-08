// swift-tools-version:5.9
// Copyright (C) 2026 Serafino Christian
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "ZTLCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ZTLCore", targets: ["ZTLCore"]),
    ],
    targets: [
        .target(name: "ZTLCore"),
        .testTarget(name: "ZTLCoreTests", dependencies: ["ZTLCore"]),
    ]
)
