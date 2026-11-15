//
//  FixFilter.swift
//  P2PGPSCore
//
//  P2P GPS — outlier rejection and accuracy-weighted smoothing.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Architecture §4 step 3: decoded packets go through a filter before they
//  reach the map or the injection engine. The filter is deliberately simple and
//  deterministic (no Kalman filter): the goal is to drop obviously wrong fixes
//  and to keep the marker from jittering, not to reconstruct a trajectory.
//
//  Stale timestamps are deliberately NOT rejected here: spec §3.3-7 says a
//  timestamp more than ±24 h from now is a *display warning*, and whether to
//  inject is up to the user setting. The UI uses `GPSFix.isStale(now:)` for the
//  warning (see ReceiverView), so a sender with a mis-set clock still shows and
//  can still be injected.
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSProtocol
#endif

/// Why a fix was rejected by ``FixFilter``.
public enum FixRejectionReason: Equatable, Sendable {
    /// Latitude / longitude outside the valid range, or Null Island.
    case invalidCoordinate
    /// Horizontal accuracy worse than the configured limit.
    case poorAccuracy(accuracyMeters: Double)
    /// The implied speed exceeds the configured maximum (a teleport).
    case implausibleJump(distanceMeters: Double, timeInterval: TimeInterval)
    /// The fix is too close to the previous one to be worth updating.
    case tooClose(distanceMeters: Double)
}

/// The outcome of filtering one fix.
public enum FixFilterDecision: Sendable {
    /// The fix passed; this is the value to display / inject.
    case accepted(GPSFix)
    /// The fix was discarded; the previous fix stays current.
    case rejected(FixRejectionReason)
}

/// A stateful, deterministic fix filter.
///
/// Not thread-safe by design: the BLE layer owns one instance and calls it from
/// its own serial context.
public struct FixFilter: Sendable {
    /// Tunable limits. Defaults are chosen for a 1 Hz pedestrian/vehicle sender.
    public struct Configuration: Sendable, Equatable {
        /// Reject fixes whose horizontal accuracy is worse than this (metres).
        public var maximumAccuracyMeters: Double
        /// Reject fixes implying a speed above this (metres per second).
        /// 120 m/s ≈ 432 km/h, comfortably above any real use.
        public var maximumSpeedMetersPerSecond: Double
        /// Smoothing weight for a new fix (0 = ignore, 1 = no smoothing).
        public var smoothingFactor: Double
        /// Reject fixes closer than this to the previous one (metres).
        public var minimumDistanceMeters: Double

        public init(
            maximumAccuracyMeters: Double = 200,
            maximumSpeedMetersPerSecond: Double = 120,
            smoothingFactor: Double = 0.5,
            minimumDistanceMeters: Double = 0
        ) {
            self.maximumAccuracyMeters = maximumAccuracyMeters
            self.maximumSpeedMetersPerSecond = maximumSpeedMetersPerSecond
            self.smoothingFactor = smoothingFactor
            self.minimumDistanceMeters = minimumDistanceMeters
        }
    }

    public var configuration: Configuration
    /// The last fix that was accepted, used as the smoothing anchor.
    public private(set) var lastAccepted: GPSFix?
    /// Number of fixes accepted / rejected so far.
    public private(set) var acceptedCount: Int = 0
    public private(set) var rejectedCount: Int = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Filters `fix` against the previous accepted fix.
    ///
    /// - Note: A stale timestamp (spec §3.3-7) is not a rejection reason.
    public mutating func process(_ fix: GPSFix) -> FixFilterDecision {
        guard fix.isUsable else {
            return reject(.invalidCoordinate)
        }

        if fix.horizontalAccuracyMeters >= 0,
           fix.horizontalAccuracyMeters > configuration.maximumAccuracyMeters {
            return reject(.poorAccuracy(accuracyMeters: fix.horizontalAccuracyMeters))
        }

        // A simulated fix may legitimately jump anywhere: the user can move the
        // debug coordinate to a different city, which would otherwise be
        // rejected as a teleport forever (the anchor never advances). Accept it
        // as-is, without smoothing, so the injected position follows the
        // simulated coordinate immediately.
        if fix.isSimulated {
            return accept(fix)
        }

        guard let previous = lastAccepted else {
            return accept(fix)
        }

        let distance = previous.distance(to: fix)
        if distance < configuration.minimumDistanceMeters {
            return reject(.tooClose(distanceMeters: distance))
        }

        let interval = max(fix.timestamp.timeIntervalSince(previous.timestamp), 0.001)
        if distance / interval > configuration.maximumSpeedMetersPerSecond {
            return reject(.implausibleJump(distanceMeters: distance, timeInterval: interval))
        }

        // Trust a precise fix more than an imprecise one: when the new fix is
        // noisier than the anchor, move towards it less.
        let accuracyRatio: Double
        if fix.horizontalAccuracyMeters > 0, previous.horizontalAccuracyMeters > 0 {
            accuracyRatio = min(1.0, max(0.1, previous.horizontalAccuracyMeters / fix.horizontalAccuracyMeters))
        } else {
            accuracyRatio = 1.0
        }
        let alpha = min(1.0, max(0.05, configuration.smoothingFactor * accuracyRatio))

        var smoothed = fix
        smoothed.latitude = previous.latitude + (fix.latitude - previous.latitude) * alpha
        smoothed.longitude = previous.longitude + (fix.longitude - previous.longitude) * alpha
        return accept(smoothed)
    }

    /// Forgets the smoothing anchor (e.g. after a disconnect).
    public mutating func reset() {
        lastAccepted = nil
    }

    private mutating func accept(_ fix: GPSFix) -> FixFilterDecision {
        lastAccepted = fix
        acceptedCount += 1
        return .accepted(fix)
    }

    private mutating func reject(_ reason: FixRejectionReason) -> FixFilterDecision {
        rejectedCount += 1
        return .rejected(reason)
    }
}
