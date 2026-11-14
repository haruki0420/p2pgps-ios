//
//  SenderStatus.swift
//  P2PGPSProtocol
//
//  P2P GPS — Status characteristic (8 bytes, sender → receiver).
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §6. Notified on every state change and as a 10-second heartbeat.
//

import Foundation

/// Errors thrown while decoding a Status packet.
public enum SenderStatusError: Error, Equatable, Sendable {
    case invalidLength(actual: Int)
    case unsupportedVersion(UInt8)
}

/// A decoded Status packet (spec §6).
public struct SenderStatus: Equatable, Sendable {
    public static let byteCount = 8
    public static let currentVersion: UInt8 = P2PGPS.protocolVersion
    public static let unknownBattery: UInt8 = 255

    /// Streaming state (spec §6 `state`).
    public enum State: UInt8, Sendable, CaseIterable {
        case idle = 0
        case streaming = 1
        case paused = 2
        case error = 3
    }

    /// `status_flags` bits (spec §6).
    public struct Flags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// Extended Location notifications are enabled.
        public static let extendedEnabled = Flags(rawValue: 1 << 0)
        /// The sender currently has a fix.
        public static let fixAvailable = Flags(rawValue: 1 << 1)
        /// The sender is charging.
        public static let charging = Flags(rawValue: 1 << 2)
        /// The sender's battery is low.
        public static let lowBattery = Flags(rawValue: 1 << 3)
    }

    /// `last_error` values (spec §6).
    public enum LastError: UInt8, Sendable, CaseIterable {
        case none = 0
        case unknownOpcode = 1
        case badLength = 2
        case locationUnavailable = 3
        case internalError = 4
    }

    public var version: UInt8
    public var state: State
    public var intervalMilliseconds: UInt16
    /// Battery percentage 0–100, or `255` when unknown.
    public var batteryPercentage: UInt8
    public var flags: Flags
    public var lastError: LastError
    /// Reserved; must be zero.
    public var reserved: UInt8

    public init(
        version: UInt8 = SenderStatus.currentVersion,
        state: State = .idle,
        intervalMilliseconds: UInt16 = ControlCommand.defaultIntervalMilliseconds,
        batteryPercentage: UInt8 = SenderStatus.unknownBattery,
        flags: Flags = [],
        lastError: LastError = .none,
        reserved: UInt8 = 0
    ) {
        self.version = version
        self.state = state
        self.intervalMilliseconds = intervalMilliseconds
        self.batteryPercentage = batteryPercentage
        self.flags = flags
        self.lastError = lastError
        self.reserved = reserved
    }

    /// Battery percentage as an optional value (nil = unknown).
    public var batteryPercentValue: Int? {
        guard batteryPercentage <= 100 else { return nil }
        return Int(batteryPercentage)
    }

    /// The status a sender reports before it has done anything.
    public static var idle: SenderStatus {
        SenderStatus()
    }

    // MARK: - Encoding

    public func encoded() -> Data {
        var data = Data(capacity: SenderStatus.byteCount)
        ByteCodec.append(version, to: &data)
        ByteCodec.append(state.rawValue, to: &data)
        ByteCodec.append(intervalMilliseconds, to: &data)
        ByteCodec.append(batteryPercentage, to: &data)
        ByteCodec.append(flags.rawValue, to: &data)
        ByteCodec.append(lastError.rawValue, to: &data)
        ByteCodec.append(reserved, to: &data)
        return data
    }

    public static func decode(_ data: Data) throws -> SenderStatus {
        guard data.count == SenderStatus.byteCount else {
            throw SenderStatusError.invalidLength(actual: data.count)
        }
        let version = data[data.startIndex]
        guard version == SenderStatus.currentVersion else {
            throw SenderStatusError.unsupportedVersion(version)
        }
        return SenderStatus(
            version: version,
            state: State(rawValue: data[data.startIndex + 1]) ?? .error,
            intervalMilliseconds: ByteCodec.read(UInt16.self, from: data, at: 2),
            batteryPercentage: data[data.startIndex + 4],
            flags: Flags(rawValue: data[data.startIndex + 5]),
            lastError: LastError(rawValue: data[data.startIndex + 6]) ?? .internalError,
            reserved: data[data.startIndex + 7]
        )
    }

    public var hexDescription: String {
        ByteCodec.hexString(encoded())
    }
}
