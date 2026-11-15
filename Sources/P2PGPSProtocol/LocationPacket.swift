//
//  LocationPacket.swift
//  P2PGPSProtocol
//
//  P2P GPS — Location Packet (20 bytes) and its flags.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §3 (p2pgps/https://github.com/haruki0420/p2pgps-protocol/blob/main/spec/protocol-v1.md). The 20-byte size is deliberate: it
//  fits in a single ATT notification at the BLE 4.0 default MTU of 23 bytes, so
//  no fragmentation or MTU negotiation is required.
//

import Foundation

/// `flags` field of the Location Packet (spec §3.1).
public struct LocationFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// A valid position is present. When clear, lat/lon are zero.
    public static let validFix = LocationFlags(rawValue: 1 << 0)
    /// `altitudeMeters` is meaningful.
    public static let altitudeValid = LocationFlags(rawValue: 1 << 1)
    /// `speedMetersPerSecond` is meaningful.
    public static let speedValid = LocationFlags(rawValue: 1 << 2)
    /// The sender is transmitting a simulated / mock position.
    public static let simulated = LocationFlags(rawValue: 1 << 3)
    /// The sender is charging.
    public static let charging = LocationFlags(rawValue: 1 << 4)
    /// The sender's battery is below 20%.
    public static let lowBattery = LocationFlags(rawValue: 1 << 5)
    /// The sender considers itself moving (e.g. speed ≥ 0.5 m/s).
    public static let moving = LocationFlags(rawValue: 1 << 6)

    /// Bit 7 is reserved and must be zero on the wire (spec §3.1).
    public static let reservedMask: UInt8 = 0x80
}

/// Errors thrown while decoding a Location Packet.
///
/// A packet that fails any of these checks must be discarded by the receiver
/// (spec §3.3); there is no "partial" packet.
public enum LocationPacketError: Error, Equatable, Sendable {
    /// The characteristic value was not exactly 20 bytes.
    case invalidLength(actual: Int)
    /// `version` was not `0x01`.
    case unsupportedVersion(UInt8)
    /// `flags` had the reserved bit 7 set.
    case reservedFlagSet(UInt8)
    /// Latitude was outside ±90.0000000°.
    case latitudeOutOfRange(Int32)
    /// Longitude was outside ±180.0000000°.
    case longitudeOutOfRange(Int32)
}

/// A decoded Location Packet (spec §3).
///
/// The wire values are stored exactly as received (`latitudeE7` /
/// `longitudeE7`), which makes round-tripping lossless and lets the receiver
/// compare packets without floating-point noise. Degrees are exposed as
/// computed properties.
public struct LocationPacket: Equatable, Sendable {
    /// Fixed packet size on the wire (spec §3).
    public static let byteCount = 20
    /// The only protocol version this implementation produces or accepts.
    public static let currentVersion: UInt8 = P2PGPS.protocolVersion
    /// Degrees are transmitted as degrees × 10^7 (spec §3).
    public static let degreesScale: Double = 10_000_000
    /// Maximum absolute latitude on the wire (±90° × 10^7).
    public static let maximumLatitudeE7: Int32 = 900_000_000
    /// Maximum absolute longitude on the wire (±180° × 10^7).
    public static let maximumLongitudeE7: Int32 = 1_800_000_000
    /// Null Island is treated as "no fix": within ±0.0001° of (0, 0).
    public static let nullIslandToleranceE7: Int32 = 1_000

    public var version: UInt8
    public var flags: LocationFlags
    public var sequence: UInt16
    /// Latitude in degrees × 10^7 (int32 on the wire).
    public var latitudeE7: Int32
    /// Longitude in degrees × 10^7 (int32 on the wire).
    public var longitudeE7: Int32
    /// Altitude in whole metres; `nil` when the sender has no altitude.
    public var altitudeMeters: Int16?
    /// Horizontal accuracy in metres; `255` = unknown / ≥ 255 m.
    public var accuracyMeters: UInt8
    /// Speed in metres per second; `255` = unknown / ≥ 255 m/s.
    public var speedMetersPerSecond: UInt8
    /// Unix epoch seconds (UTC).
    public var timestamp: UInt32

    // MARK: - Init

    /// Designated initialiser using raw wire values.
    public init(
        version: UInt8 = LocationPacket.currentVersion,
        flags: LocationFlags,
        sequence: UInt16,
        latitudeE7: Int32,
        longitudeE7: Int32,
        altitudeMeters: Int16?,
        accuracyMeters: UInt8,
        speedMetersPerSecond: UInt8,
        timestamp: UInt32
    ) {
        self.version = version
        self.flags = flags
        self.sequence = sequence
        self.latitudeE7 = latitudeE7
        self.longitudeE7 = longitudeE7
        self.altitudeMeters = altitudeMeters
        self.accuracyMeters = accuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.timestamp = timestamp
    }

    /// Convenience initialiser taking degrees and metres.
    ///
    /// Values are rounded to the nearest wire unit. Out-of-range coordinates
    /// are clamped so that a sender can never emit an undecodable packet.
    public init(
        flags: LocationFlags,
        sequence: UInt16,
        latitude: Double,
        longitude: Double,
        altitudeMeters: Int16?,
        accuracyMeters: UInt8,
        speedMetersPerSecond: UInt8,
        timestamp: UInt32
    ) {
        let latE7 = Int32((latitude * LocationPacket.degreesScale).rounded())
        let lonE7 = Int32((longitude * LocationPacket.degreesScale).rounded())
        self.init(
            flags: flags,
            sequence: sequence,
            latitudeE7: min(max(latE7, -LocationPacket.maximumLatitudeE7), LocationPacket.maximumLatitudeE7),
            longitudeE7: min(max(lonE7, -LocationPacket.maximumLongitudeE7), LocationPacket.maximumLongitudeE7),
            altitudeMeters: altitudeMeters,
            accuracyMeters: accuracyMeters,
            speedMetersPerSecond: speedMetersPerSecond,
            timestamp: timestamp
        )
    }

    // MARK: - Derived values

    /// Latitude in degrees.
    public var latitude: Double {
        Double(latitudeE7) / LocationPacket.degreesScale
    }

    /// Longitude in degrees.
    public var longitude: Double {
        Double(longitudeE7) / LocationPacket.degreesScale
    }

    /// Unix epoch seconds as a `Date`.
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    /// `true` when the packet claims a valid fix (spec §3.1 bit 0).
    public var hasValidFixFlag: Bool {
        flags.contains(.validFix)
    }

    /// `true` when the coordinate is within ±0.0001° of (0, 0).
    ///
    /// Such a packet is structurally valid but is treated as "no fix"
    /// (spec §3.3 rule 5, Null Island).
    public var isNullIsland: Bool {
        abs(latitudeE7) <= LocationPacket.nullIslandToleranceE7
            && abs(longitudeE7) <= LocationPacket.nullIslandToleranceE7
    }

    /// Whether the receiver should use this packet as a position.
    ///
    /// Spec §3.3: a packet is usable when `VALID_FIX` is set and the position
    /// is not Null Island. Everything else is accepted on the wire (and may be
    /// shown as a status) but must not drive location injection.
    public var isUsableFix: Bool {
        hasValidFixFlag && !isNullIsland
    }

    /// Whether the sender's timestamp is more than ±24 h from `now`
    /// (spec §3.3 rule 7). Stale packets are displayed with a warning; whether
    /// they are injected is a user setting.
    public func isStale(now: Date = Date(), tolerance: TimeInterval = 24 * 60 * 60) -> Bool {
        abs(now.timeIntervalSince(date)) > tolerance
    }

    // MARK: - Encoding

    /// Serialises the packet to its fixed 20-byte wire form (spec §3).
    public func encoded() -> Data {
        var data = Data(capacity: LocationPacket.byteCount)
        ByteCodec.append(version, to: &data)
        ByteCodec.append(flags.rawValue, to: &data)
        ByteCodec.append(sequence, to: &data)
        ByteCodec.append(latitudeE7, to: &data)
        ByteCodec.append(longitudeE7, to: &data)
        ByteCodec.append(altitudeMeters ?? 0, to: &data)
        ByteCodec.append(accuracyMeters, to: &data)
        ByteCodec.append(speedMetersPerSecond, to: &data)
        ByteCodec.append(timestamp, to: &data)
        return data
    }

    /// Parses a 20-byte characteristic value, rejecting anything the receiver
    /// must discard (spec §3.3 rules 1–4).
    public static func decode(_ data: Data) throws -> LocationPacket {
        guard data.count == LocationPacket.byteCount else {
            throw LocationPacketError.invalidLength(actual: data.count)
        }

        let version = data[data.startIndex]
        guard version == LocationPacket.currentVersion else {
            throw LocationPacketError.unsupportedVersion(version)
        }

        let flagsRaw = data[data.startIndex + 1]
        guard flagsRaw & LocationFlags.reservedMask == 0 else {
            throw LocationPacketError.reservedFlagSet(flagsRaw)
        }

        let sequence = ByteCodec.read(UInt16.self, from: data, at: 2)
        let latitudeE7 = ByteCodec.read(Int32.self, from: data, at: 4)
        let longitudeE7 = ByteCodec.read(Int32.self, from: data, at: 8)
        let altitudeRaw = ByteCodec.read(Int16.self, from: data, at: 12)
        let accuracy = data[data.startIndex + 14]
        let speed = data[data.startIndex + 15]
        let timestamp = ByteCodec.read(UInt32.self, from: data, at: 16)

        guard (-LocationPacket.maximumLatitudeE7...LocationPacket.maximumLatitudeE7).contains(latitudeE7) else {
            throw LocationPacketError.latitudeOutOfRange(latitudeE7)
        }
        guard (-LocationPacket.maximumLongitudeE7...LocationPacket.maximumLongitudeE7).contains(longitudeE7) else {
            throw LocationPacketError.longitudeOutOfRange(longitudeE7)
        }

        let flags = LocationFlags(rawValue: flagsRaw)
        return LocationPacket(
            version: version,
            flags: flags,
            sequence: sequence,
            latitudeE7: latitudeE7,
            longitudeE7: longitudeE7,
            altitudeMeters: flags.contains(.altitudeValid) ? altitudeRaw : nil,
            accuracyMeters: accuracy,
            speedMetersPerSecond: speed,
            timestamp: timestamp
        )
    }

    /// The packet a characteristic read returns before anything has been sent:
    /// `flags = 0` (no fix), everything else zero (spec §1.1).
    public static var invalid: LocationPacket {
        LocationPacket(
            flags: [],
            sequence: 0,
            latitudeE7: 0,
            longitudeE7: 0,
            altitudeMeters: nil,
            accuracyMeters: 0,
            speedMetersPerSecond: 0,
            timestamp: 0
        )
    }

    /// Hex dump for the diagnostics screen.
    public var hexDescription: String {
        ByteCodec.hexString(encoded())
    }
}
