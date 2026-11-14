//
//  ReceiverController.swift
//  P2PGPSApp
//
//  P2P GPS — Receiver screen state: BLE fixes, map trail, injection.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Architecture §4 data flow: BLE notify → decode → filter → map, and (only
//  when the user turned injection on) → LocationSimulationEngine.
//

#if canImport(UIKit)
import Combine
import CoreLocation
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
import P2PGPSInjection
#endif

/// Coordinates the receiver's BLE central, the map trail and the injection
/// engine. All callbacks are delivered on the main queue by the BLE layer.
final class ReceiverController: ObservableObject {
    // MARK: - Published state

    /// Recent accepted fixes, oldest first (bounded).
    @Published private(set) var trail: [CLLocationCoordinate2D] = []
    /// The user asked for injection (the toggle's state).
    @Published private(set) var wantsInjection: Bool
    /// A coordinate has actually been handed to the device.
    @Published private(set) var isInjecting = false
    /// When the last coordinate was injected.
    @Published private(set) var lastInjectedAt: Date?
    /// Last user-facing problem (already phrased with a recovery step).
    @Published var errorMessage: String?

    // MARK: - Collaborators

    let central: ReceiverCentral
    let engine: LocationSimulationEngine
    let settings: SettingsStore

    // MARK: - Private state

    private var cancellables: Set<AnyCancellable> = []
    private var lastTrailAppend = Date.distantPast
    private var lastInjectedCoordinate: CLLocationCoordinate2D?
    private let maximumTrailPoints = 120
    private let log = LogStore.shared

    // MARK: - Init

    init(
        central: ReceiverCentral = ReceiverCentral(),
        engine: LocationSimulationEngine = .shared,
        settings: SettingsStore = .shared
    ) {
        self.central = central
        self.engine = engine
        self.settings = settings
        self.wantsInjection = settings.injectionEnabled

        central.autoReconnect = settings.autoReconnect
        central.onError = { [weak self] message in
            self?.errorMessage = message
        }

        central.$latestFix
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fix in
                self?.handle(fix)
            }
            .store(in: &cancellables)

        engine.$lastError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle / BLE

    /// Starts scanning when the screen appears.
    func onAppear() {
        engine.refreshMountState()
        if wantsInjection, let fix = central.latestFix {
            inject(fix)
        }
        if central.state == .idle {
            central.startScanning()
        }
    }

    func startScanning() {
        errorMessage = nil
        central.startScanning()
    }

    func connect(to sender: DiscoveredSender) {
        errorMessage = nil
        central.connect(to: sender)
    }

    func disconnect() {
        if isInjecting || wantsInjection {
            setInjection(false)
        }
        central.disconnect()
    }

    // MARK: - Injection

    /// Turns location injection on or off. Turning it on requires a received fix;
    /// turning it off always clears the device session.
    func setInjection(_ enabled: Bool) {
        wantsInjection = enabled
        settings.injectionEnabled = enabled
        errorMessage = nil

        if enabled {
            if let fix = central.latestFix, fix.isUsable {
                inject(fix)
            } else {
                errorMessage = "有効な位置をまだ受信していません。送信側が測位できるまで待ってから再試行してください。"
            }
        } else {
            isInjecting = false
            lastInjectedCoordinate = nil
            lastInjectedAt = nil
            if settings.useTLocationURLSchemeFallback {
                URLSchemeLocationFallback.clear()
            } else {
                engine.clear()
            }
        }
    }

    /// Toggles injection from the readout plate.
    func toggleInjection() {
        setInjection(!wantsInjection)
    }

    // MARK: - Fix handling

    private func handle(_ fix: GPSFix) {
        appendToTrail(fix)
        if wantsInjection {
            inject(fix)
        }
    }

    private func appendToTrail(_ fix: GPSFix) {
        guard fix.isUsable else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTrailAppend) >= 1.0 else { return }

        if let last = trail.last {
            let distance = GPSFix.distance(
                fromLatitude: last.latitude,
                fromLongitude: last.longitude,
                toLatitude: fix.latitude,
                toLongitude: fix.longitude
            )
            guard distance >= 2 else { return }
        }

        trail.append(CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude))
        if trail.count > maximumTrailPoints {
            trail.removeFirst(trail.count - maximumTrailPoints)
        }
        lastTrailAppend = now
    }

    private func inject(_ fix: GPSFix) {
        guard fix.isUsable else { return }

        if settings.useTLocationURLSchemeFallback {
            URLSchemeLocationFallback.simulate(latitude: fix.latitude, longitude: fix.longitude)
            isInjecting = true
            lastInjectedAt = Date()
            return
        }

        // Skip redundant FFI calls: the engine itself resends every 5 s.
        if let last = lastInjectedCoordinate {
            let distance = GPSFix.distance(
                fromLatitude: last.latitude,
                fromLongitude: last.longitude,
                toLatitude: fix.latitude,
                toLongitude: fix.longitude
            )
            let elapsed = Date().timeIntervalSince(lastInjectedAt ?? .distantPast)
            if distance < 0.5 && elapsed < 3 {
                return
            }
        }

        lastInjectedCoordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
        lastInjectedAt = Date()
        isInjecting = true
        engine.set(latitude: fix.latitude, longitude: fix.longitude)
        log.debug("注入座標を更新しました")
    }

    // MARK: - Derived UI state

    var senderName: String? {
        central.state.senderName
    }

    var coordinateText: String {
        guard let fix = central.latestFix else { return "—" }
        return fix.coordinateDescription(decimalPlaces: 7)
    }

    var injectedCoordinateText: String {
        guard let fix = central.latestFix else { return "—" }
        return fix.coordinateDescription(decimalPlaces: 5)
    }

    var accuracyText: String {
        P2PFormat.accuracy(central.latestFix?.horizontalAccuracyMeters)
    }
}
#endif
