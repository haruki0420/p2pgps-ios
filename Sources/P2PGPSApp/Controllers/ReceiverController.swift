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
    private var isKeepAliveRunning = false
    private var lastEngineSimulating = false
    private var shouldAttemptTunnelReconnect = false
    /// Which backends this process has asked to simulate a coordinate on.
    ///
    /// Tracked per backend (not as one flag) because the setting can change
    /// while injection is ON: switching "TLocation の URL スキームに委譲" must
    /// still clear the backend that was used before the switch (review R-15).
    /// `stopInjectionSession()` / `handleBackendChange()` only send a clear for
    /// a backend that was actually requested, so toggling injection OFF before
    /// any fix does not produce a spurious FFI error (review R-1).
    private var requestedEmbeddedSimulation = false
    private var requestedURLSchemeSimulation = false
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

        // An unexpected disconnect must clear the device-side simulation
        // session; otherwise the engine keeps resending the last coordinate
        // every 5 s while the UI still claims injection is active. Keep
        // `wantsInjection` so a reconnect resumes automatically.
        central.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if !state.isConnected {
                    // Do not draw a trail across two different senders or
                    // leave the map centered on a stale location.
                    self.trail.removeAll()
                    self.lastTrailAppend = .distantPast
                }
                guard !state.isConnected, self.isInjecting else { return }
                self.log.info("送信元が切断されたため注入セッションを停止しました")
                self.stopInjectionSession()
            }
            .store(in: &cancellables)

        engine.$lastError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                self.errorMessage = message
                // A failed FFI call means the device session is gone; the
                // toggle must not keep claiming "injecting" (review L-3).
                // While the URL-scheme backend is active, an embedded-engine
                // clear/error must not drop the URL backend's state (R-15).
                if !self.settings.useTLocationURLSchemeFallback {
                    self.isInjecting = false
                }
            }
            .store(in: &cancellables)

        engine.$isSimulating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] simulating in
                guard let self else { return }
                if simulating {
                    // Clear a transient error only on the recovery transition,
                    // not on every 5 s resend tick.
                    if !self.lastEngineSimulating {
                        self.errorMessage = nil
                    }
                    self.lastEngineSimulating = true
                    return
                }
                self.lastEngineSimulating = false
                // Same backend guard as above (review R-15).
                if !self.settings.useTLocationURLSchemeFallback {
                    self.isInjecting = false
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

        // Switching the injection backend while injection is ON must clear the
        // old backend before resuming on the new one (review R-15).
        settings.$useTLocationURLSchemeFallback
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleBackendChange()
            }
            .store(in: &cancellables)

        // A deferred tunnel rebuild runs as soon as the simulation session
        // releases the RSD endpoint (review M4). Defer one run-loop turn so the
        // engine's own main-queue completion (`isSimulating = false`) runs
        // first; otherwise the reconnect would be deferred again because the
        // session still looked active (review R-5).
        NotificationCenter.default.publisher(for: .p2pLocationSimulationSessionEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.attemptDeferredTunnelReconnect(trigger: "the location simulation ending")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle / BLE

    /// Starts scanning when the screen appears.
    func onAppear() {
        engine.refreshMountState()
        updateKeepAliveState()
        if wantsInjection {
            // The app's tunnel is only needed for DDI mounting, but starting it
            // here means the first injection attempt does not have to wait.
            // Route through the same guard as foreground retries so an active
            // location-simulation session is never disturbed.
            shouldAttemptTunnelReconnect = true
            attemptDeferredTunnelReconnect(trigger: "Receiver 画面の表示")
        }
        if wantsInjection, let fix = central.latestFix {
            inject(fix)
        }
        if central.state == .idle {
            central.startScanning()
        }
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
    ///
    /// Every backend that was actually used is cleared independently of the
    /// current setting, so switching the backend while injection is ON cannot
    /// leave the other backend's session behind (review R-15). The clear is
    /// sent whenever a simulation was requested, even if the engine has not
    /// finished `set()` yet: "injection ON → OFF immediately" must still clear
    /// the device-side session (review R-1).
    private func stopInjectionSession() {
        isInjecting = false
        lastInjectedCoordinate = nil
        lastInjectedAt = nil
        updateKeepAliveState()
        clearRequestedBackends()
    }

    /// Clears every backend this process asked to simulate on.
    ///
    /// The setting may have changed since the request, so this must not look at
    /// `settings.useTLocationURLSchemeFallback` to pick one backend: the
    /// embedded engine and the URL-scheme delegation are cleared independently
    /// (review R-15).
    private func clearRequestedBackends() {
        let needsEmbeddedClear = requestedEmbeddedSimulation
            || engine.isSimulating
            || engine.sessionOpen
            || engine.isWorking
        let needsURLClear = requestedURLSchemeSimulation
        requestedEmbeddedSimulation = false
        requestedURLSchemeSimulation = false

        if needsEmbeddedClear {
            engine.clear()
        }
        if needsURLClear {
            URLSchemeLocationFallback.clear()
        }
    }

    /// The injection backend was switched in Settings.
    ///
    /// Clear the backend that was in use (so the device does not keep the old
    /// session), then resume with the new backend if injection is still ON
    /// (review R-15).
    private func handleBackendChange() {
        let wasInjecting = wantsInjection
        // Force the next `inject` to go through instead of being skipped as a
        // redundant update.
        lastInjectedCoordinate = nil
        lastURLSchemeDelegation = .distantPast
        clearRequestedBackends()

        guard wasInjecting else { return }
        if let fix = central.latestFix, fix.isUsable {
            inject(fix)
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
            requestedURLSchemeSimulation = true
            isInjecting = true
            lastInjectedAt = now
            // `UIApplication.open` only tells us whether the URL was handed to
            // the system; reflect a failure in the UI instead of claiming a
            // successful injection (review R-6).
            URLSchemeLocationFallback.simulate(latitude: fix.latitude, longitude: fix.longitude) { success in
                guard !success else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.isInjecting = false
                    self?.errorMessage = "TLocation を開けませんでした。URL スキーム委譲を OFF にするか、TLocation をインストールし直してください。"
                }
            }
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
        requestedEmbeddedSimulation = true
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

    // MARK: - Background keep-alive (review M1 / R-4)

    /// Keeps the low-accuracy location session running for as long as injection
    /// is ON — even if the user navigates away from the Receiver screen — so a
    /// background transition cannot suspend the 5-second resend loop
    /// (review R-4). This trades battery for injection reliability; the setting
    /// can turn it off.
    private func updateKeepAliveState() {
        let shouldRun = wantsInjection && settings.keepAliveLocationUpdates
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
