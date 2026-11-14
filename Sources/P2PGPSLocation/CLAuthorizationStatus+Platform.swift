//
//  CLAuthorizationStatus+Platform.swift
//  P2PGPSLocation
//
//  P2P GPS — CoreLocation authorization differences between iOS and macOS.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  `swift test` builds every target for macOS, so this module must compile
//  there too. macOS has no "when in use" authorization:
//  `CLAuthorizationStatus.authorizedWhenInUse` is explicitly marked
//  `@available(macOS, unavailable)`, and only `.authorizedAlways` exists.
//  Keeping the platform split in one place avoids scattering `#if os(iOS)`
//  through the services and keeps the iOS behaviour unchanged.
//

import CoreLocation

extension CLAuthorizationStatus {
    /// Whether the app may start location updates.
    ///
    /// - iOS/iPadOS: "Always" and "When in Use" both allow updates.
    /// - macOS: only "Always" exists, so only `.authorizedAlways` qualifies.
    var p2pIsAuthorized: Bool {
        #if os(iOS)
        return self == .authorizedAlways || self == .authorizedWhenInUse
        #else
        return self == .authorizedAlways
        #endif
    }
}
