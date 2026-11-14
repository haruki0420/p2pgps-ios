//
//  ControlCommand.swift
//  P2PGPSProtocol
//
//  P2P GPS — Control characteristic commands (receiver → sender).
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §5. One command per GATT write; the sender acknowledges via the Status
//  characteristic (notify), not by a write response.
//

import Foundation

/// Errors thrown while decoding a Control characteristic write.
public enum ControlCommandError: Error, Equatable, Sendable {
    /// A zero-length write.
    case empty
    /// The opcode is not defined in v1 (or is reserved, e.g. `AUTH = 0x10`).
    case unknownOpcode(UInt8)
    /// The payload length does not match the opcode's definition.
    case badLength(opcode: UInt8, expected: Int, actual: Int)
}

/// A Control characteristic command (spec §5).
public enum ControlCommand: Equatable, Sendable {
    /// Start streaming. `intervalMilliseconds` of 0 means "use the default".
    case start(intervalMilliseconds: UInt16)
    /// Stop streaming; advertising continues.
    case stop
    /// Change the send interval (also while streaming).
    case setInterval(intervalMilliseconds: UInt16)
    /// Send the next notify immediately (once).
    case requestFix
    /// Enable or disable Extended Location notifications.
    case setExtended(enabled: Bool)
    /// Reset to defaults: interval 1000 ms, extended off, sequence 0.
    case reset

    // MARK: - Constants

    public static let startOpcode: UInt8 = 0x01
    public static let stopOpcode: UInt8 = 0x02
    public static let setIntervalOpcode: UInt8 = 0x03
    public static let requestFixOpcode: UInt8 = 0x04
    public static let setExtendedOpcode: UInt8 = 0x05
    public static let resetOpcode: UInt8 = 0x7F
    /// Reserved for a future v2 application-layer authentication command.
    public static let authOpcode: UInt8 = 0x10

    /// Default interval when START carries 0 (spec §5).
    public static let defaultIntervalMilliseconds: UInt16 = 1_000
    /// Minimum accepted interval (spec §5).
    public static let minimumIntervalMilliseconds: UInt16 = 100
    /// Maximum accepted interval (spec §5).
    public static let maximumIntervalMilliseconds: UInt16 = 60_000

    // MARK: - Derived values

    /// The opcode byte for this command.
    public var opcode: UInt8 {
        switch self {
        case .start: return Self.startOpcode
        case .stop: return Self.stopOpcode
        case .setInterval: return Self.setIntervalOpcode
        case .requestFix: return Self.requestFixOpcode
        case .setExtended: return Self.setExtendedOpcode
        case .reset: return Self.resetOpcode
        }
    }

    /// The interval a sender should actually use, applying the spec's
    /// "0 = default, otherwise clamp to 100…60000" rule (spec §5).
    public var resolvedIntervalMilliseconds: UInt16? {
        switch self {
        case .start(let interval), .setInterval(let interval):
            return Self.normalizedInterval(interval)
        case .stop, .requestFix, .setExtended, .reset:
            return nil
        }
    }

    /// Normalises a raw interval per spec §5.
    public static func normalizedInterval(_ raw: UInt16) -> UInt16 {
        if raw == 0 {
            return defaultIntervalMilliseconds
        }
        return min(max(raw, minimumIntervalMilliseconds), maximumIntervalMilliseconds)
    }

    // MARK: - Encoding

    /// Serialises the command (1–3 bytes).
    public func encoded() -> Data {
        var data = Data(capacity: 3)
        data.append(opcode)
        switch self {
        case .start(let interval), .setInterval(let interval):
            ByteCodec.append(interval, to: &data)
        case .setExtended(let enabled):
            data.append(enabled ? 1 : 0)
        case .stop, .requestFix, .reset:
            break
        }
        return data
    }

    /// Parses a Control characteristic write.
    ///
    /// Unknown opcodes and malformed lengths are reported as errors so the
    /// sender can set `last_error` in the Status packet (spec §5); the write
    /// itself is simply ignored.
    public static func decode(_ data: Data) throws -> ControlCommand {
        guard let opcode = data.first else {
            throw ControlCommandError.empty
        }

        switch opcode {
        case startOpcode:
            try requireLength(3, opcode: opcode, data: data)
            return .start(intervalMilliseconds: ByteCodec.read(UInt16.self, from: data, at: 1))
        case stopOpcode:
            try requireLength(1, opcode: opcode, data: data)
            return .stop
        case setIntervalOpcode:
            try requireLength(3, opcode: opcode, data: data)
            return .setInterval(intervalMilliseconds: ByteCodec.read(UInt16.self, from: data, at: 1))
        case requestFixOpcode:
            try requireLength(1, opcode: opcode, data: data)
            return .requestFix
        case setExtendedOpcode:
            try requireLength(2, opcode: opcode, data: data)
            return .setExtended(enabled: data[data.startIndex + 1] != 0)
        case resetOpcode:
            try requireLength(1, opcode: opcode, data: data)
            return .reset
        default:
            throw ControlCommandError.unknownOpcode(opcode)
        }
    }

    private static func requireLength(_ expected: Int, opcode: UInt8, data: Data) throws {
        guard data.count == expected else {
            throw ControlCommandError.badLength(opcode: opcode, expected: expected, actual: data.count)
        }
    }
}
