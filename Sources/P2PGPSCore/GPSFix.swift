//
//  GPSFix.swift
//  P2PGPSCore
//
//  P2P GPS — platform-independent location fix model.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSProtocol
#endif

/// A single location fix, independent of CoreLocation so that the filtering and
/// display logic can be unit-tested on macOS.
public struct GPSFix: Equatable, Sendable, Identifiable {
    /// Stable identity for SwiftUI lists / map annotations.
    public let id: UUID
    /// Latitude in degrees.
    public var latitude: Double
    /// Longitude in degrees.
    public var longitude: Double
    /// Altitude in metres, when known.
    public var altitudeMeters: Double?
    /// Horizontal accuracy in metres (lower is better).
    public var horizontalAccuracyMeters: Double
    /// Vertical accuracy in metres, when known.
    public var verticalAccuracyMeters: Double?
    /// Speed in metres per second, when known.
    public var speedMetersPerSecond: Double?
    /// Course over ground in degrees, when known.
    public var courseDegrees: Double?
    /// When the fix was measured (sender clock, UTC).
    public var timestamp: Date
    /// When this app received the fix.
    public var receivedAt: Date
    /// Whether the sender says the fix is simulated / mocked.
    public var isSimulated: Bool
    /// Provider reported by the sender, when known.
    public var provider: ExtendedLocationPacket.Provider?
    /// Sender battery percentage, when known.
    public var batteryPercentage: UInt8?
    /// Number of satellites, when known.
    public var satellites: UInt8?
    /// Protocol sequence number this fix arrived with.
    public var sequence: UInt16?

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double? = nil,
        horizontalAccuracyMeters: Double = 0,
        verticalAccuracyMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        courseDegrees: Double? = nil,
        timestamp: Date = Date(),
        receivedAt: Date = Date(),
        isSimulated: Bool = false,
        provider: ExtendedLocationPacket.Provider? = nil,
        batteryPercentage: UInt8? = nil,
        satellites: UInt8? = nil,
        sequence: UInt16? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
        self.timestamp = timestamp
        self.receivedAt = receivedAt
        self.isSimulated = isSimulated
        self.provider = provider
        self.batteryPercentage = batteryPercentage
        self.satellites = satellites
        self.sequence = sequence
    }

    /// Whether the fix is usable for location injection.
    public var isUsable: Bool {
        (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(abs(latitude) <= 0.0001 && abs(longitude) <= 0.0001)
    }

    /// Whether the sender's timestamp is more than ±24 h from `now`
    /// (spec §3.3 rule 7). Stale fixes are displayed with a warning.
    public func isStale(now: Date = Date(), tolerance: TimeInterval = 24 * 60 * 60) -> Bool {
        abs(now.timeIntervalSince(timestamp)) > tolerance
    }

    /// Great-circle distance in metres from another fix (haversine).
    public func distance(to other: GPSFix) -> Double {
        Self.distance(
            fromLatitude: latitude,
            fromLongitude: longitude,
            toLatitude: other.latitude,
            toLongitude: other.longitude
        )
    }

    /// Haversine distance in metres between two coordinates.
    public static func distance(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = fromLatitude * .pi / 180
        let lat2 = toLatitude * .pi / 180
        let deltaLat = (toLatitude - fromLatitude) * .pi / 180
        let deltaLon = (toLongitude - fromLongitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Short coordinate string for banners and lists (5 decimal places ≈ 1 m).
    ///
    /// The format locale is pinned so the decimal separator is always "."
    /// (review L-18).
    public func coordinateDescription(decimalPlaces: Int = 5) -> String {
        String(
            format: "%.\(decimalPlaces)f, %.\(decimalPlaces)f",
            locale: Locale(identifier: "en_US_POSIX"),
            arguments: [latitude, longitude]
        )
    }
}
