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
//  Review M1: the Receiver keeps a low-accuracy CoreLocation session alive
//  (`BackgroundKeepAlive`) while injection is on, so iOS does not suspend the
//  process and stop the 5-second resend loop. Review M4: a background → active
//  transition rebuilds the app's RSD tunnel, deferred while a simulation
//  session is still using the single-occupancy endpoint.
//

#if canImport(UIKit)
import Combine
import CoreLocation
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
import P2PGPSInjection
import P2PGPSLocation
import P2PGPSProtocol
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

    private let backgroundKeepAlive = BackgroundKeepAlive()
    private var cancellables: Set<AnyCancellable> = []
    private var lastTrailAppend = Date.distantPast
    private var lastInjectedCoordinate: CLLocationCoordinate2D?
    private var lastURLSchemeDelegation = Date.distantPast
    private var isOnScreen = false
    private var isKeepAliveRunning = false
    private var shouldAttemptTunnelReconnect = false
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
                // A failed FFI call means the device session is gone; the
                // toggle must not keep claiming "injecting" (review L-3).
                self?.isInjecting = false
            }
            .store(in: &cancellables)

        engine.$isSimulating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] simulating in
                if !simulating {
                    self?.isInjecting = false
                }
            }
            .store(in: &cancellables)

        // Settings changes are applied to the BLE layer / keep-alive live
        // (review M11).
        settings.$autoReconnect
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.central.autoReconnect = value
            }
            .store(in: &cancellables)

        settings.$keepAliveLocationUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateKeepAliveState()
            }
            .store(in: &cancellables)

        settings.$senderIntervalMilliseconds
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                guard let self, self.central.state.isConnected else { return }
                self.central.send(.setInterval(intervalMilliseconds: interval))
            }
            .store(in: &cancellables)

        settings.$extendedLocationEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, self.central.state.isConnected else { return }
                self.central.setExtendedEnabled(enabled)
            }
            .store(in: &cancellables)

        // A deferred tunnel rebuild runs as soon as the simulation session
        // releases the RSD endpoint (review M4).
        NotificationCenter.default.publisher(for: .p2pLocationSimulationSessionEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.attemptDeferredTunnelReconnect(trigger: "the location simulation ending")
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle / BLE

    /// Starts scanning when the screen appears.
    func onAppear() {
        isOnScreen = true
        engine.refreshMountState()
        updateKeepAliveState()
        if wantsInjection {
            // The app's tunnel is only needed for DDI mounting, but starting it
            // here means the first injection attempt does not have to wait.
            startTunnelAfterPendingLocationCommands()
        }
        if wantsInjection, let fix = central.latestFix {
            inject(fix)
        }
        if central.state == .idle {
            central.startScanning()
        }
    }

    /// Stops the background keep-alive when leaving the Receiver screen.
    func onDisappear() {
        isOnScreen = false
        updateKeepAliveState()
    }

    /// Scene went to the background: remember that the tunnel may need a rebuild
    /// when we come back (review M4, ported from TLocation).
    func handleScenePhaseBackground() {
        shouldAttemptTunnelReconnect = true
    }

    /// Scene became active again: rebuild the tunnel unless a simulation is
    /// still using the endpoint.
    func handleScenePhaseActive() {
        attemptDeferredTunnelReconnect(trigger: "a return to the foreground")
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
        // Keep the user's injection preference; only the device session stops
        // (review L-4).
        stopInjectionSession()
        central.disconnect(userInitiated: true)
    }

    // MARK: - Injection

    /// Turns location injection on or off. Turning it on requires a received fix;
    /// turning it off always clears the device session.
    func setInjection(_ enabled: Bool) {
        wantsInjection = enabled
        settings.injectionEnabled = enabled
        errorMessage = nil

        if enabled {
            updateKeepAliveState()
            startTunnelAfterPendingLocationCommands()
            if let fix = central.latestFix, fix.isUsable {
                inject(fix)
            } else {
                errorMessage = "有効な位置をまだ受信していません。送信側が測位できるまで待ってから再試行してください。"
            }
        } else {
            stopInjectionSession()
        }
    }

    /// Toggles injection from the readout plate.
    func toggleInjection() {
        setInjection(!wantsInjection)
    }

    /// Stops the device session without changing the user's preference.
    private func stopInjectionSession() {
        isInjecting = false
        lastInjectedCoordinate = nil
        lastInjectedAt = nil
        updateKeepAliveState()
        if settings.useTLocationURLSchemeFallback {
            URLSchemeLocationFallback.clear()
        } else {
            engine.clear()
        }
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
            guard URLSchemeLocationFallback.isAvailable else {
                isInjecting = false
                errorMessage = "TLocation がインストールされていません。URL スキーム委譲を OFF にするか、TLocation をインストールしてください。"
                return
            }
            // Throttle: opening a URL once per fix would be wasteful (review L-5).
            let now = Date()
            guard now.timeIntervalSince(lastURLSchemeDelegation) >= 1.0 else { return }
            lastURLSchemeDelegation = now
            URLSchemeLocationFallback.simulate(latitude: fix.latitude, longitude: fix.longitude)
            isInjecting = true
            lastInjectedAt = now
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
        // Coordinates are logged only at the user's configured precision
        // (review M13 / spec §8).
        log.logCoordinate(
            "注入座標",
            latitude: fix.latitude,
            longitude: fix.longitude,
            decimalPlaces: settings.logCoordinateDecimalPlaces
        )
    }

    // MARK: - Background keep-alive (review M1)

    private func updateKeepAliveState() {
        let shouldRun = isOnScreen && wantsInjection && settings.keepAliveLocationUpdates
        if shouldRun {
            guard !isKeepAliveRunning else { return }
            isKeepAliveRunning = true
            backgroundKeepAlive.start()
            log.info("Receiver のバックグラウンド維持を開始しました")
        } else {
            guard isKeepAliveRunning else { return }
            isKeepAliveRunning = false
            backgroundKeepAlive.stop()
            log.info("Receiver のバックグラウンド維持を停止しました")
        }
    }

    // MARK: - Tunnel lifecycle (review M4)

    private func attemptDeferredTunnelReconnect(trigger: String) {
        guard shouldAttemptTunnelReconnect else { return }
        guard !engine.isSimulating, !engine.sessionOpen else {
            log.info("トンネル再接続を保留: 位置シミュレーションが継続中")
            return
        }
        shouldAttemptTunnelReconnect = false
        log.info("トンネルを再構築します（\(trigger)）")
        startTunnelAfterPendingLocationCommands()
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
