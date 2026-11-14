//
//  BackgroundKeepAlive.swift
//  P2PGPSLocation
//
//  P2P GPS — low-accuracy location session that keeps the app alive.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Architecture §2.4: both roles keep a low-accuracy location session running so
//  iOS does not suspend the process while the BLE link or the injection loop is
//  supposed to stay alive. This is the same technique TLocation uses; it never
//  drives the map or the injected coordinate.
//

import Combine
import CoreLocation
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Low-accuracy location session used purely as a background keep-alive.
public final class BackgroundKeepAlive: NSObject, ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let log = LogStore.shared

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = true
        #endif
        authorizationStatus = manager.authorizationStatus
    }

    /// Starts the keep-alive session, requesting authorization if needed.
    public func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            begin()
        case .denied, .restricted:
            log.warning("バックグラウンド維持用の位置情報が許可されていません")
        @unknown default:
            break
        }
    }

    /// Stops the keep-alive session.
    public func stop() {
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        isRunning = false
        log.info("バックグラウンド維持用の位置情報を停止しました")
    }

    private func begin() {
        guard !isRunning else { return }
        isRunning = true
        manager.startUpdatingLocation()
        log.info("バックグラウンド維持用の位置情報を開始しました")
    }
}

extension BackgroundKeepAlive: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isRunning || manager.authorizationStatus == .authorizedAlways {
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                begin()
            default:
                break
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // The fixes themselves are irrelevant; running the session is the point.
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the session registered; CoreLocation recovers on its own.
    }
}
