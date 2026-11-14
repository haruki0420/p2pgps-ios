//
//  AppRole.swift
//  P2PGPSCore
//
//  P2P GPS — which half of the link this device is running.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation

/// The two roles of the app (architecture §2.2).
public enum AppRole: String, CaseIterable, Identifiable, Sendable {
    /// iPhone: reads CoreLocation and notifies Location Packets as a BLE peripheral.
    case sender
    /// iPad: scans as a BLE central, displays the position and injects it.
    case receiver

    public var id: String { rawValue }

    /// Navigation title / role picker label.
    public var title: String {
        switch self {
        case .sender: return "送信する"
        case .receiver: return "受信する"
        }
    }

    /// One-line explanation under the title.
    public var subtitle: String {
        switch self {
        case .sender: return "この iPhone の現在地を BLE で iPad に送ります"
        case .receiver: return "iPhone / Android から受け取った位置を iPad に反映します"
        }
    }

    /// SF Symbol shown in the role picker.
    public var symbolName: String {
        switch self {
        case .sender: return "location.fill"
        case .receiver: return "ipad.and.arrow.forward"
        }
    }

    /// The role this device should default to: iPad receives, iPhone sends.
    public static func `default`(isPad: Bool) -> AppRole {
        isPad ? .receiver : .sender
    }
}
