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
//  installed and set up separately. Coordinates are deliberately NOT written to
//  the log (review M7); only the fact that a delegation happened is logged.
//
//  The completion handlers report whether `UIApplication.open` actually handed
//  the URL to the system, so the caller can drop the "injecting" state instead
//  of claiming success unconditionally (review R-6).
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

    /// Whether a TLocation build that handles the scheme is installed.
    ///
    /// `canOpenURL` requires the scheme in `LSApplicationQueriesSchemes`
    /// (Info.plist); it is checked before delegating so an absent TLocation
    /// shows a clear error instead of silently doing nothing.
    public static var isAvailable: Bool {
        #if canImport(UIKit)
        guard let url = clearURL else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    /// `tlocation://simulate-location?lat=…&lon=…`
    public static func simulateURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "simulate-location"
        components.queryItems = [
            URLQueryItem(name: "lat", value: coordinateString(latitude)),
            URLQueryItem(name: "lon", value: coordinateString(longitude)),
        ]
        return components.url
    }

    /// `tlocation://clear-location`
    public static var clearURL: URL? {
        URL(string: "\(scheme)://clear-location")
    }

    /// Opens TLocation to simulate the coordinate.
    ///
    /// - Parameter completion: Called on the main queue with `true` when the
    ///   system accepted the URL, `false` when it could not be opened (or the
    ///   platform cannot open URLs at all).
    /// - Returns: `false` immediately only when the URL is malformed / the
    ///   platform cannot open URLs.
    @discardableResult
    public static func simulate(
        latitude: Double,
        longitude: Double,
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        guard let url = simulateURL(latitude: latitude, longitude: longitude) else {
            completion?(false)
            return false
        }
        return open(url, completion: completion)
    }

    /// Opens TLocation to clear the simulated location.
    @discardableResult
    public static func clear(completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let url = clearURL else {
            completion?(false)
            return false
        }
        return open(url, completion: completion)
    }

    /// Locale-independent decimal formatting: a comma decimal separator would
    /// break the URL query (review L-18).
    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
    }

    private static func open(_ url: URL, completion: ((Bool) -> Void)? = nil) -> Bool {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                LogStore.shared.info("TLocation の URL スキームへ委譲しました")
            } else {
                LogStore.shared.warning("TLocation の URL スキームを開けませんでした")
            }
            if Thread.isMainThread {
                completion?(success)
            } else {
                DispatchQueue.main.async { completion?(success) }
            }
        }
        return true
        #else
        LogStore.shared.warning("このプラットフォームでは URL スキーム委譲を利用できません")
        completion?(false)
        return false
        #endif
    }
}
