// swift-tools-version: 6.0
//
// P2P GPS for iOS / iPadOS
// Copyright (C) 2026 haruki0420 and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This package is built two ways:
//
//   * `xtool dev build` (Linux / WSL / macOS) — SwiftPM cross-builds the
//     `P2PGPSApp` library product for iOS and xtool wraps it into an `.app`.
//   * `xcodegen generate` + `xcodebuild` — CI only. XcodeGen compiles every
//     source directory as a single module (see `project.yml`), so the
//     `#if SWIFT_PACKAGE` import guards in the sources are what keep the two
//     build systems compatible.
//
// The `idevice` C target wraps the vendored `idevice.h` / `module.modulemap`
// pair copied from TLocation. The static library itself (`libidevice_ffi.a`,
// ~92 MB, arm64 iOS) is NOT checked in: run `scripts/fetch-vendor.sh` (or
// `scripts/fetch-vendor.ps1` on Windows) before building for a device.
//
// `-L` must be an absolute path because SwiftPM runs the linker from an
// arbitrary working directory; `#filePath` is the only portable way to derive
// the package directory from the manifest.

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .standardizedFileURL
    .path
let vendorDirectory = "\(packageDirectory)/Vendor/idevice"

let package = Package(
    name: "p2pgps-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // The app itself. `xtool.yml` names this product explicitly.
        .library(
            name: "P2PGPSApp",
            targets: ["P2PGPSApp"]
        ),
        // Exposed separately so the protocol layer can be consumed by tools
        // (and so `swift test` on macOS only needs the Foundation-only code).
        .library(
            name: "P2PGPSProtocol",
            targets: ["P2PGPSProtocol"]
        ),
        .library(
            name: "P2PGPSCore",
            targets: ["P2PGPSCore"]
        ),
    ],
    targets: [
        // MARK: Pure Swift (macOS + iOS)

        .target(
            name: "P2PGPSProtocol",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "P2PGPSCore",
            dependencies: ["P2PGPSProtocol"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: iOS frameworks

        .target(
            name: "P2PGPSBLE",
            dependencies: ["P2PGPSProtocol", "P2PGPSCore"],
            // CoreBluetooth exists on macOS as well, so this target compiles
            // during `swift test`; the language mode matches the rest of the
            // framework code (see README "Swift 6 と言語モード").
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "P2PGPSLocation",
            dependencies: ["P2PGPSCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "P2PGPSInjection",
            dependencies: ["P2PGPSCore", "idevice"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: App

        .target(
            name: "P2PGPSApp",
            dependencies: [
                "P2PGPSProtocol",
                "P2PGPSCore",
                "P2PGPSBLE",
                "P2PGPSLocation",
                "P2PGPSInjection",
            ],
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: Vendored C module

        .target(
            name: "idevice",
            path: "Vendor/idevice",
            // `idevice.h` and `module.modulemap` live directly in Vendor/idevice
            // (same layout as TLocation's Xcode target, which finds the module
            // through SWIFT_INCLUDE_PATHS).
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                // The static library is arm64/iOS only; never apply these flags
                // when the host builds the package for macOS (swift test).
                .unsafeFlags(
                    ["-L\(vendorDirectory)", "-lidevice_ffi"],
                    .when(platforms: [.iOS])
                ),
            ]
        ),

        // MARK: Tests (macOS)

        .testTarget(
            name: "P2PGPSProtocolTests",
            dependencies: ["P2PGPSProtocol", "P2PGPSCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
