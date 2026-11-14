//
//  AppSettings.swift
//  P2PGPSCore
//
//  P2P GPS — user settings model and persistence.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSProtocol
#endif

/// All user-visible settings, with the defaults required by the specification.
///
/// Security-relevant defaults come straight from spec §8: location injection is
/// **off** until the user turns it on, and auto-connect only ever targets a
/// sender the user picked.
public struct AppSettings: Equatable, Sendable {
    /// Re-scan and reconnect to the last sender after a disconnect.
    public var autoReconnect: Bool
    /// Whether received fixes are injected into the device's location.
    /// Spec §8: default **off**.
    public var injectionEnabled: Bool
    /// Decimal places used when coordinates are written to the log.
    /// Spec §8: default 5 (≈ 1 m).
    public var logCoordinateDecimalPlaces: Int
    /// Target IP for the on-device RSD tunnel (LocalDevVPN exposes 10.7.0.1).
    public var targetDeviceIPAddress: String
    /// Delegate injection to TLocation's `tlocation://` URL scheme instead of
    /// the embedded engine (architecture §2.3 item 6).
    public var useTLocationURLSchemeFallback: Bool
    /// Sender send interval in milliseconds.
    public var senderIntervalMilliseconds: UInt16
    /// Keep a low-accuracy location session alive in the background.
    public var keepAliveLocationUpdates: Bool
    /// Ask the sender for Extended Location notifications.
    public var extendedLocationEnabled: Bool
    /// The last sender the user connected to (local name), for auto-reconnect.
    public var lastSenderName: String?
    /// The last sender's CoreBluetooth identifier, stored as a string.
    public var lastSenderIdentifier: String?

    public static let defaultTargetDeviceIPAddress = "10.7.0.1"

    public init(
        autoReconnect: Bool = true,
        injectionEnabled: Bool = false,
        logCoordinateDecimalPlaces: Int = 5,
        targetDeviceIPAddress: String = AppSettings.defaultTargetDeviceIPAddress,
        useTLocationURLSchemeFallback: Bool = false,
        senderIntervalMilliseconds: UInt16 = ControlCommand.defaultIntervalMilliseconds,
        keepAliveLocationUpdates: Bool = true,
        extendedLocationEnabled: Bool = false,
        lastSenderName: String? = nil,
        lastSenderIdentifier: String? = nil
    ) {
        self.autoReconnect = autoReconnect
        self.injectionEnabled = injectionEnabled
        self.logCoordinateDecimalPlaces = logCoordinateDecimalPlaces
        self.targetDeviceIPAddress = targetDeviceIPAddress
        self.useTLocationURLSchemeFallback = useTLocationURLSchemeFallback
        self.senderIntervalMilliseconds = senderIntervalMilliseconds
        self.keepAliveLocationUpdates = keepAliveLocationUpdates
        self.extendedLocationEnabled = extendedLocationEnabled
        self.lastSenderName = lastSenderName
        self.lastSenderIdentifier = lastSenderIdentifier
    }
}

/// `UserDefaults` keys. One place so the app and tests agree on persistence.
public enum SettingsKey {
    public static let autoReconnect = "p2pgps.autoReconnect"
    public static let injectionEnabled = "p2pgps.injectionEnabled"
    public static let logCoordinateDecimalPlaces = "p2pgps.logCoordinateDecimalPlaces"
    public static let targetDeviceIPAddress = "p2pgps.targetDeviceIPAddress"
    public static let useTLocationURLSchemeFallback = "p2pgps.useTLocationURLSchemeFallback"
    public static let senderIntervalMilliseconds = "p2pgps.senderIntervalMilliseconds"
    public static let keepAliveLocationUpdates = "p2pgps.keepAliveLocationUpdates"
    public static let extendedLocationEnabled = "p2pgps.extendedLocationEnabled"
    public static let lastSenderName = "p2pgps.lastSenderName"
    public static let lastSenderIdentifier = "p2pgps.lastSenderIdentifier"
}

/// Observable settings store backed by `UserDefaults`.
///
/// Marked `@unchecked Sendable` because `UserDefaults` is thread-safe and the
/// published properties are only mutated from the main thread by the UI.
public final class SettingsStore: ObservableObject, @unchecked Sendable {
    public static let shared = SettingsStore()

    @Published public var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: SettingsKey.autoReconnect) }
    }

    @Published public var injectionEnabled: Bool {
        didSet { defaults.set(injectionEnabled, forKey: SettingsKey.injectionEnabled) }
    }

    @Published public var logCoordinateDecimalPlaces: Int {
        didSet { defaults.set(logCoordinateDecimalPlaces, forKey: SettingsKey.logCoordinateDecimalPlaces) }
    }

    @Published public var targetDeviceIPAddress: String {
        didSet { defaults.set(targetDeviceIPAddress, forKey: SettingsKey.targetDeviceIPAddress) }
    }

    @Published public var useTLocationURLSchemeFallback: Bool {
        didSet { defaults.set(useTLocationURLSchemeFallback, forKey: SettingsKey.useTLocationURLSchemeFallback) }
    }

    @Published public var senderIntervalMilliseconds: UInt16 {
        didSet { defaults.set(Int(senderIntervalMilliseconds), forKey: SettingsKey.senderIntervalMilliseconds) }
    }

    @Published public var keepAliveLocationUpdates: Bool {
        didSet { defaults.set(keepAliveLocationUpdates, forKey: SettingsKey.keepAliveLocationUpdates) }
    }

    @Published public var extendedLocationEnabled: Bool {
        didSet { defaults.set(extendedLocationEnabled, forKey: SettingsKey.extendedLocationEnabled) }
    }

    @Published public var lastSenderName: String? {
        didSet { defaults.set(lastSenderName, forKey: SettingsKey.lastSenderName) }
    }

    @Published public var lastSenderIdentifier: String? {
        didSet { defaults.set(lastSenderIdentifier, forKey: SettingsKey.lastSenderIdentifier) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.object(forKey: SettingsKey.senderIntervalMilliseconds) as? Int
        let interval = storedInterval.map { UInt16(clamping: $0) } ?? ControlCommand.defaultIntervalMilliseconds
        let storedPlaces = defaults.object(forKey: SettingsKey.logCoordinateDecimalPlaces) as? Int
        let places = storedPlaces.map { min(max($0, 0), 7) } ?? 5
        let storedIP = defaults.string(forKey: SettingsKey.targetDeviceIPAddress)

        autoReconnect = defaults.object(forKey: SettingsKey.autoReconnect) as? Bool ?? true
        injectionEnabled = defaults.object(forKey: SettingsKey.injectionEnabled) as? Bool ?? false
        logCoordinateDecimalPlaces = places
        targetDeviceIPAddress = storedIP.flatMap { $0.isEmpty ? nil : $0 }
            ?? AppSettings.defaultTargetDeviceIPAddress
        useTLocationURLSchemeFallback = defaults.object(forKey: SettingsKey.useTLocationURLSchemeFallback) as? Bool ?? false
        senderIntervalMilliseconds = interval
        keepAliveLocationUpdates = defaults.object(forKey: SettingsKey.keepAliveLocationUpdates) as? Bool ?? true
        extendedLocationEnabled = defaults.object(forKey: SettingsKey.extendedLocationEnabled) as? Bool ?? false
        lastSenderName = defaults.string(forKey: SettingsKey.lastSenderName)
        lastSenderIdentifier = defaults.string(forKey: SettingsKey.lastSenderIdentifier)
    }

    /// The current values as a plain value type (safe to hand to background code).
    public var snapshot: AppSettings {
        AppSettings(
            autoReconnect: autoReconnect,
            injectionEnabled: injectionEnabled,
            logCoordinateDecimalPlaces: logCoordinateDecimalPlaces,
            targetDeviceIPAddress: targetDeviceIPAddress,
            useTLocationURLSchemeFallback: useTLocationURLSchemeFallback,
            senderIntervalMilliseconds: senderIntervalMilliseconds,
            keepAliveLocationUpdates: keepAliveLocationUpdates,
            extendedLocationEnabled: extendedLocationEnabled,
            lastSenderName: lastSenderName,
            lastSenderIdentifier: lastSenderIdentifier
        )
    }
}
