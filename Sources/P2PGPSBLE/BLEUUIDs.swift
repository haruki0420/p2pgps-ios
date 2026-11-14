//
//  BLEUUIDs.swift
//  P2PGPSBLE
//
//  P2P GPS — CoreBluetooth identifiers derived from the protocol constants.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import CoreBluetooth
#if SWIFT_PACKAGE
import P2PGPSProtocol
#endif

/// `CBUUID`s for the GATT profile in spec §1.
///
/// The strings live in `P2PGPSProtocol` (Foundation-only, unit-tested); this
/// type is the CoreBluetooth bridge.
public enum BLEUUID {
    public static let service = CBUUID(string: P2PGPS.serviceUUID)
    public static let location = CBUUID(string: P2PGPS.locationCharacteristicUUID)
    public static let control = CBUUID(string: P2PGPS.controlCharacteristicUUID)
    public static let status = CBUUID(string: P2PGPS.statusCharacteristicUUID)
    public static let extended = CBUUID(string: P2PGPS.extendedLocationCharacteristicUUID)

    public static let deviceInformationService = CBUUID(string: P2PGPS.deviceInformationServiceUUID)
    public static let manufacturerName = CBUUID(string: P2PGPS.manufacturerNameCharacteristicUUID)
    public static let modelNumber = CBUUID(string: P2PGPS.modelNumberCharacteristicUUID)
    public static let firmwareRevision = CBUUID(string: P2PGPS.firmwareRevisionCharacteristicUUID)

    /// All characteristics a receiver subscribes to.
    public static let receiverNotifications: [CBUUID] = [location, status, extended]
}

/// How strong the last advertisement / connection looked.
///
/// Kept as a small enum so the UI can render four signal bars without doing
/// arithmetic, and so VoiceOver has a word for it.
public enum SignalQuality: Int, Comparable, Sendable, CaseIterable {
    case none = 0
    case weak = 1
    case fair = 2
    case good = 3
    case strong = 4

    public static func < (lhs: SignalQuality, rhs: SignalQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Maps a BLE RSSI in dBm to a bar count.
    public init(rssi: Int) {
        switch rssi {
        case ...(-85): self = .weak
        case ...(-75): self = .fair
        case ...(-60): self = .good
        default: self = .strong
        }
    }

    /// Japanese label for accessibility.
    public var localizedDescription: String {
        switch self {
        case .none: return "未接続"
        case .weak: return "弱い"
        case .fair: return "やや弱い"
        case .good: return "良好"
        case .strong: return "強い"
        }
    }
}
