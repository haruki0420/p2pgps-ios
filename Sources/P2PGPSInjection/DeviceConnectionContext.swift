//
//  DeviceConnectionContext.swift
//  P2PGPSInjection
//
//  P2P GPS — where the on-device RSD service is reachable.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Device/DeviceConnectionContext.swift`), derived from StikDebug,
//  AGPL-3.0. Copyright (C) Stephen and the StikDebug / TLocation contributors.
//
//  LocalDevVPN exposes the device itself as 10.7.0.1, which is the only way an
//  app can reach its own RSD service (port 49152).
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Target address used for the on-device RSD tunnel.
public enum DeviceConnectionContext {
    /// LocalDevVPN's loopback address for the device itself.
    public static let defaultTargetIPAddress = AppSettings.defaultTargetDeviceIPAddress

    /// The user-configured target IP, falling back to `10.7.0.1`.
    public static var targetIPAddress: String {
        let stored = UserDefaults.standard
            .string(forKey: SettingsKey.targetDeviceIPAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else {
            return defaultTargetIPAddress
        }
        return stored
    }
}
