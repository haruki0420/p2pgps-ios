//
//  URLSchemeLocationFallback.swift
//  P2PGPSInjection
//
//  P2P GPS — delegate location injection to TLocation's URL scheme.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Architecture §2.3 item 6: when the embedded engine cannot be used, the user
//  can hand injection to an installed TLocation build via its documented URL
//  scheme:
//
//    tlocation://simulate-location?lat=37.3349&lon=-122.0090
//    tlocation://clear-location
//
//  This is a fallback, not the primary path: it requires TLocation to be
//  installed and set up separately.
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Builds and opens TLocation's location URL scheme.
public enum URLSchemeLocationFallback {
    /// The URL scheme TLocation registers.
    public static let scheme = "tlocation"

    /// `tlocation://simulate-location?lat=…&lon=…`
    public static func simulateURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "simulate-location"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.7f", latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.7f", longitude)),
        ]
        return components.url
    }

    /// `tlocation://clear-location`
    public static var clearURL: URL? {
        URL(string: "\(scheme)://clear-location")
    }

    /// Opens TLocation to simulate the coordinate. Returns `false` when the
    /// platform cannot open URLs (macOS build) or the URL is malformed.
    @discardableResult
    public static func simulate(latitude: Double, longitude: Double) -> Bool {
        guard let url = simulateURL(latitude: latitude, longitude: longitude) else {
            return false
        }
        return open(url)
    }

    /// Opens TLocation to clear the simulated location.
    @discardableResult
    public static func clear() -> Bool {
        guard let url = clearURL else { return false }
        return open(url)
    }

    private static func open(_ url: URL) -> Bool {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        LogStore.shared.info("TLocation の URL スキームへ委譲しました: \(url.absoluteString)")
        return true
        #else
        LogStore.shared.warning("このプラットフォームでは URL スキーム委譲を利用できません")
        return false
        #endif
    }
}
