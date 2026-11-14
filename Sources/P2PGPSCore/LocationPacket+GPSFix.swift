//
//  LocationPacket+GPSFix.swift
//  P2PGPSCore
//
//  P2P GPS — conversions between the wire packet and the app model.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSProtocol
#endif

extension LocationPacket {
    /// Builds the app model from a decoded packet.
    ///
    /// `extended` is merged in when the sender supports the optional Extended
    /// Location characteristic (spec §4).
    public func gpsFix(
        receivedAt: Date = Date(),
        extended: ExtendedLocationPacket? = nil
    ) -> GPSFix {
        var fix = GPSFix(
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: altitudeMeters.map { Double($0) },
            horizontalAccuracyMeters: accuracyMeters == 255 ? -1 : Double(accuracyMeters),
            speedMetersPerSecond: speedMetersPerSecond == 255 ? nil : Double(speedMetersPerSecond),
            timestamp: date,
            receivedAt: receivedAt,
            isSimulated: flags.contains(.simulated),
            sequence: sequence
        )
        if let extended {
            fix.provider = extended.provider
            fix.batteryPercentage = extended.batteryPercentValue.map { UInt8($0) }
            fix.satellites = extended.satellites == 255 ? nil : extended.satellites
            fix.courseDegrees = extended.courseDegrees
            fix.verticalAccuracyMeters = extended.verticalAccuracyMeters == 255
                ? nil
                : Double(extended.verticalAccuracyMeters)
        }
        return fix
    }

    /// Builds a packet from an app model.
    ///
    /// - Parameters:
    ///   - fix: The fix to transmit.
    ///   - sequence: The sender's next sequence number.
    ///   - extraFlags: Additional flags (charging, low battery, moving…).
    public init(fix: GPSFix, sequence: UInt16, extraFlags: LocationFlags = []) {
        var flags: LocationFlags = []
        if fix.isUsable {
            flags.insert(.validFix)
        }
        if fix.altitudeMeters != nil {
            flags.insert(.altitudeValid)
        }
        if fix.speedMetersPerSecond != nil {
            flags.insert(.speedValid)
        }
        if fix.isSimulated {
            flags.insert(.simulated)
        }
        flags.formUnion(extraFlags)

        let altitude: Int16? = fix.altitudeMeters.map { value in
            let rounded = Int16(clamping: Int(value.rounded(.towardZero)))
            return rounded
        }
        let accuracy: UInt8 = fix.horizontalAccuracyMeters < 0
            ? 255
            : UInt8(clamping: Int(fix.horizontalAccuracyMeters.rounded()))
        let speed: UInt8 = fix.speedMetersPerSecond.map { value in
            UInt8(clamping: Int(value.rounded()))
        } ?? 255

        self.init(
            flags: flags,
            sequence: sequence,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitudeMeters: altitude,
            accuracyMeters: accuracy,
            speedMetersPerSecond: speed,
            timestamp: UInt32(clamping: Int(fix.timestamp.timeIntervalSince1970))
        )
    }
}

extension ExtendedLocationPacket {
    /// Builds an Extended packet from an app model.
    public init(fix: GPSFix) {
        let battery: UInt8 = fix.batteryPercentage ?? ExtendedLocationPacket.unknownByte
        let satellites: UInt8 = fix.satellites ?? ExtendedLocationPacket.unknownByte
        let course: UInt16
        if let degrees = fix.courseDegrees {
            let centidegrees = Int((degrees * 100).rounded()) % 36_000
            course = UInt16((centidegrees + 36_000) % 36_000)
        } else {
            course = ExtendedLocationPacket.unknownCourse
        }
        let vertical: UInt8
        if let accuracy = fix.verticalAccuracyMeters {
            vertical = UInt8(clamping: Int(accuracy.rounded()))
        } else {
            vertical = ExtendedLocationPacket.unknownByte
        }
        self.init(
            provider: fix.provider ?? .unknown,
            batteryPercentage: battery,
            satellites: satellites,
            courseCentidegrees: course,
            verticalAccuracyMeters: vertical
        )
    }
}
