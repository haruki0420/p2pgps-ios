//
//  SenderLocationService.swift
//  P2PGPSLocation
//
//  P2P GPS — CoreLocation source for the Sender role.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Architecture §2.4: the sender keeps `location` + `bluetooth-peripheral`
//  background modes. This service runs a continuous, high-accuracy location
//  session while sending, and publishes platform-independent `GPSFix` values so
//  the BLE layer never sees CoreLocation types.
//
//  This target also builds for macOS during `swift test`, so every iOS-only
//  CoreLocation API is behind `#if os(iOS)` and authorization checks go through
//  `CLAuthorizationStatus.p2pIsAuthorized` (see
//  `CLAuthorizationStatus+Platform.swift`).
//

import Combine
import CoreLocation
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Battery / charging state of the sender, when the platform exposes it.
public enum DeviceBattery {
    /// Battery percentage 0–100, or `nil` when unknown.
    public static var percentage: UInt8? {
        #if canImport(UIKit)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return UInt8((level * 100).rounded())
        #else
        return nil
        #endif
    }

    /// Whether the device is currently charging.
    public static var isCharging: Bool {
        #if canImport(UIKit)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return device.batteryState == .charging || device.batteryState == .full
        #else
        return false
        #endif
    }
}

/// Continuous CoreLocation source for the Sender role.
public final class SenderLocationService: NSObject, ObservableObject {
    // MARK: - Published state

    @Published public private(set) var latestFix: GPSFix?
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public private(set) var isUpdating = false
    @Published public private(set) var lastError: String?

    // MARK: - Configuration

    /// Called on the main queue for every accepted fix.
    public var onFix: ((GPSFix) -> Void)?

    // MARK: - Private state

    private let manager = CLLocationManager()
    private let log = LogStore.shared
    private var wantsUpdates = false

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        #endif
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Public API

    /// Requests authorization if needed and starts continuous updates.
    public func start() {
        wantsUpdates = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            log.info("位置情報の許可を要求します")
            manager.requestAlwaysAuthorization()
        } else if status.p2pIsAuthorized {
            beginUpdates()
        } else {
            lastError = "位置情報の使用が許可されていません。設定 > プライバシーとセキュリティ > 位置情報サービスで許可してください。"
            log.error(lastError ?? "")
        }
    }

    /// Stops continuous updates.
    public func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
        isUpdating = false
        log.info("位置情報の更新を停止しました")
    }

    /// Requests a single fix (used by REQUEST_FIX and by the manual refresh).
    public func requestOneShot() {
        guard manager.authorizationStatus.p2pIsAuthorized else {
            start()
            return
        }
        manager.requestLocation()
    }

    /// Re-reads authorization (after returning from Settings).
    public func refreshAuthorization() {
        publishAuthorization(manager.authorizationStatus)
    }

    // MARK: - Private

    private func beginUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
        log.info("位置情報の更新を開始しました")
    }

    private func publishAuthorization(_ status: CLAuthorizationStatus) {
        guard status != authorizationStatus else { return }
        authorizationStatus = status
        if status.p2pIsAuthorized {
            if wantsUpdates { beginUpdates() }
        } else if status == .denied || status == .restricted {
            lastError = "位置情報の使用が許可されていません。設定 > プライバシーとセキュリティ > 位置情報サービスで許可してください。"
        }
    }

    private func makeFix(from location: CLLocation) -> GPSFix {
        let altitude: Double? = location.verticalAccuracy >= 0 ? location.altitude : nil
        let speed: Double? = location.speed >= 0 ? location.speed : nil
        let course: Double? = location.course >= 0 ? location.course : nil
        return GPSFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeMeters: altitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            verticalAccuracyMeters: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
            speedMetersPerSecond: speed,
            courseDegrees: course,
            timestamp: location.timestamp,
            receivedAt: Date(),
            isSimulated: false,
            provider: .gps,
            batteryPercentage: DeviceBattery.percentage,
            satellites: nil
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension SenderLocationService: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        publishAuthorization(manager.authorizationStatus)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0 else { return }
        let fix = makeFix(from: location)
        latestFix = fix
        onFix?(fix)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (indoors, tunnel) are normal; the session recovers.
        log.warning("位置情報の取得に失敗しました: \(error.localizedDescription)")
        lastError = "位置情報を取得できません。屋外または Wi-Fi 接続のある場所で再試行してください。"
    }
}
