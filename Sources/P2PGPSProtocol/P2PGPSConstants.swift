//
//  P2PGPSConstants.swift
//  P2PGPSProtocol
//
//  P2P GPS — BLE protocol v1 identifiers and constants.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  The normative specification is `p2pgps-protocol/spec/protocol-v1.md`
//  (mirrored at `p2pgps/https://github.com/haruki0420/p2pgps-protocol/blob/main/spec/protocol-v1.md`). Do not change any value here
//  without changing the specification for all three repositories at once.
//

import Foundation

/// Protocol-wide constants for P2P GPS BLE v1.
///
/// Deliberately named `P2PGPS` rather than `P2PGPSProtocol` because a type with
/// the same name as its enclosing SwiftPM module cannot be referenced cleanly.
public enum P2PGPS {
    /// Wire protocol version carried by every packet.
    public static let protocolVersion: UInt8 = 0x01

    // MARK: - GATT UUIDs (spec §1)

    /// P2P GPS Service.
    public static let serviceUUID = "B1E5A000-9C3D-4E7A-8F20-1A2B3C4D5E6F"
    /// Location Packet characteristic (20 bytes, read + notify).
    public static let locationCharacteristicUUID = "B1E5A001-9C3D-4E7A-8F20-1A2B3C4D5E6F"
    /// Control characteristic (1–3 bytes, write + write-without-response).
    public static let controlCharacteristicUUID = "B1E5A002-9C3D-4E7A-8F20-1A2B3C4D5E6F"
    /// Status characteristic (8 bytes, read + notify).
    public static let statusCharacteristicUUID = "B1E5A003-9C3D-4E7A-8F20-1A2B3C4D5E6F"
    /// Extended Location characteristic (8 bytes, read + notify).
    public static let extendedLocationCharacteristicUUID = "B1E5A004-9C3D-4E7A-8F20-1A2B3C4D5E6F"

    // MARK: - Device Information Service (spec §1)

    public static let deviceInformationServiceUUID = "0000180A-0000-1000-8000-00805F9B34FB"
    public static let manufacturerNameCharacteristicUUID = "00002A29-0000-1000-8000-00805F9B34FB"
    public static let modelNumberCharacteristicUUID = "00002A24-0000-1000-8000-00805F9B34FB"
    public static let firmwareRevisionCharacteristicUUID = "00002A26-0000-1000-8000-00805F9B34FB"

    public static let manufacturerName = "P2PGPS"
    public static let firmwareRevision = "1.0.0"

    // MARK: - Advertising (spec §1.2)

    /// Every sender's local name starts with this prefix; receivers ignore
    /// anything else they happen to see on the service UUID.
    public static let localNamePrefix = "P2PGPS-"

    /// Which platform a sender runs on, as it appears in the advertised name.
    public enum SenderPlatform: String, Sendable, CaseIterable {
        case ios = "IOS"
        case android = "ANDROID"

        /// Value for the Device Information Service "Model Number" field.
        public var modelNumber: String {
            switch self {
            case .ios: return "iPhone"
            case .android: return "Android"
            }
        }
    }

    /// Builds a local name of the form `P2PGPS-<PLATFORM>-<XXXX>`.
    ///
    /// - Parameters:
    ///   - platform: The sender platform.
    ///   - suffix: Exactly four hexadecimal characters. Uppercased if needed.
    public static func localName(platform: SenderPlatform, suffix: String) -> String {
        "\(localNamePrefix)\(platform.rawValue)-\(suffix.uppercased())"
    }

    /// Builds a local name with a random four-hex-digit suffix.
    public static func randomLocalName(platform: SenderPlatform) -> String {
        let value = UInt16.random(in: 0...UInt16.max)
        return localName(platform: platform, suffix: String(format: "%04X", value))
    }

    /// Whether an advertised name is one of ours (spec §1.2).
    public static func isP2PGPSLocalName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.hasPrefix(localNamePrefix)
    }

    /// Extracts the platform from a local name, if it is one of ours.
    public static func platform(fromLocalName name: String) -> SenderPlatform? {
        guard name.hasPrefix(localNamePrefix) else { return nil }
        let remainder = name.dropFirst(localNamePrefix.count)
        guard let dash = remainder.firstIndex(of: "-") else { return nil }
        return SenderPlatform(rawValue: String(remainder[..<dash]))
    }
}
