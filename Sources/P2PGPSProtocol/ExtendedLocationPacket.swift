//
//  ExtendedLocationPacket.swift
//  P2PGPSProtocol
//
//  P2P GPS — Extended Location Packet (8 bytes, optional).
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §4. Senders that support it notify this characteristic as well; a
//  receiver must work without it.
//

import Foundation

/// Errors thrown while decoding an Extended Location Packet.
public enum ExtendedLocationPacketError: Error, Equatable, Sendable {
    case invalidLength(actual: Int)
    case unsupportedVersion(UInt8)
}

/// A decoded Extended Location Packet (spec §4).
public struct ExtendedLocationPacket: Equatable, Sendable {
    public static let byteCount = 8
    public static let currentVersion: UInt8 = P2PGPS.protocolVersion
    /// `batteryPercentage` / `satellites` / `verticalAccuracyMeters` value
    /// meaning "unknown".
    public static let unknownByte: UInt8 = 255
    /// `courseCentidegrees` value meaning "unknown".
    public static let unknownCourse: UInt16 = 65_535

    /// Position provider reported by the sender (spec §4 `provider`).
    public enum Provider: UInt8, Sendable, CaseIterable {
        case unknown = 0
        case gps = 1
        case network = 2
        case fused = 3
        case manual = 4

        /// Maps an unknown on-wire value to `.unknown` instead of failing:
        /// the field is informational only.
        public init(wireValue: UInt8) {
            self = Provider(rawValue: wireValue) ?? .unknown
        }
    }

    public var version: UInt8
    public var provider: Provider
    /// Battery percentage 0–100, or `255` when unknown.
    public var batteryPercentage: UInt8
    /// Number of satellites, or `255` when unknown.
    public var satellites: UInt8
    /// Course over ground in hundredths of a degree (0–35999), or `65535`.
    public var courseCentidegrees: UInt16
    /// Vertical accuracy in metres, or `255` when unknown.
    public var verticalAccuracyMeters: UInt8
    /// Reserved; must be zero.
    public var reserved: UInt8

    public init(
        version: UInt8 = ExtendedLocationPacket.currentVersion,
        provider: Provider,
        batteryPercentage: UInt8 = ExtendedLocationPacket.unknownByte,
        satellites: UInt8 = ExtendedLocationPacket.unknownByte,
        courseCentidegrees: UInt16 = ExtendedLocationPacket.unknownCourse,
        verticalAccuracyMeters: UInt8 = ExtendedLocationPacket.unknownByte,
        reserved: UInt8 = 0
    ) {
        self.version = version
        self.provider = provider
        self.batteryPercentage = batteryPercentage
        self.satellites = satellites
        self.courseCentidegrees = courseCentidegrees
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.reserved = reserved
    }

    /// Course over ground in degrees, or `nil` when unknown.
    public var courseDegrees: Double? {
        guard courseCentidegrees != ExtendedLocationPacket.unknownCourse else { return nil }
        return Double(courseCentidegrees) / 100
    }

    /// Battery percentage as an optional value (nil = unknown).
    public var batteryPercentValue: Int? {
        guard batteryPercentage <= 100 else { return nil }
        return Int(batteryPercentage)
    }

    // MARK: - Encoding

    public func encoded() -> Data {
        var data = Data(capacity: ExtendedLocationPacket.byteCount)
        ByteCodec.append(version, to: &data)
        ByteCodec.append(provider.rawValue, to: &data)
        ByteCodec.append(batteryPercentage, to: &data)
        ByteCodec.append(satellites, to: &data)
        ByteCodec.append(courseCentidegrees, to: &data)
        ByteCodec.append(verticalAccuracyMeters, to: &data)
        ByteCodec.append(reserved, to: &data)
        return data
    }

    public static func decode(_ data: Data) throws -> ExtendedLocationPacket {
        guard data.count == ExtendedLocationPacket.byteCount else {
            throw ExtendedLocationPacketError.invalidLength(actual: data.count)
        }
        let version = data[data.startIndex]
        guard version == ExtendedLocationPacket.currentVersion else {
            throw ExtendedLocationPacketError.unsupportedVersion(version)
        }
        return ExtendedLocationPacket(
            version: version,
            provider: Provider(wireValue: data[data.startIndex + 1]),
            batteryPercentage: data[data.startIndex + 2],
            satellites: data[data.startIndex + 3],
            courseCentidegrees: ByteCodec.read(UInt16.self, from: data, at: 4),
            verticalAccuracyMeters: data[data.startIndex + 6],
            reserved: data[data.startIndex + 7]
        )
    }

    /// The value a characteristic read returns before anything has been sent.
    public static var invalid: ExtendedLocationPacket {
        ExtendedLocationPacket(provider: .unknown)
    }

    public var hexDescription: String {
        ByteCodec.hexString(encoded())
    }
}
