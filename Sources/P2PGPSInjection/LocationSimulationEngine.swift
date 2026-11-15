//
//  LocationSimulationEngine.swift
//  P2PGPSInjection
//
//  P2P GPS — on-device location simulation engine.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Device/IdeviceFFIBridge.swift`, the `simulate_location` /
//  `clear_simulated_location` half), derived from StikDebug
//  (https://github.com/StikDebug/StikDebug), AGPL-3.0.
//  Copyright (C) Stephen Bove and the StikDebug / TLocation contributors.
//
//  The FFI call sequence is unchanged from upstream. What was added is the
//  `LocationSimulationEngine` facade: a main-thread-observable object that owns
//  the 5-second resend loop (architecture §4 step 6) and translates the
//  upstream status codes into the two-sentence Japanese errors DESIGN.md asks
//  for. All FFI calls still run on the single serial
//  `LocationSimulationCommandQueue`, because the RSD endpoint is
//  single-occupancy.
//

import Combine
import Darwin
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif
import idevice

/// Posted on the main thread when the injection session or its resend loop
/// ends, i.e. when the single-occupancy RSD endpoint becomes free again.
///
/// Public so the app target can observe it (review M4).
public extension Notification.Name {
    static let p2pLocationSimulationSessionEnded = Notification.Name("jp.haruki0420.p2pgps.locationSimulationSessionEnded")
}

// MARK: - Upstream status codes

enum LocationSimulationStatus {
    static let ok: Int32 = 0
    static let invalidIP: Int32 = 1
    static let pairingRead: Int32 = 2
    static let providerCreate: Int32 = 3
    static let remoteServer: Int32 = 9
    static let locationSimulation: Int32 = 10
    static let locationSet: Int32 = 11
    static let locationClear: Int32 = 12
}

// MARK: - Session handles (confined to LocationSimulationCommandQueue)

enum LocationSimulationState {
    static var adapter: OpaquePointer?
    static var handshake: OpaquePointer?
    static var remoteServer: OpaquePointer?
    static var locationSimulation: OpaquePointer?

    static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
        // Every teardown goes through here, so this is the one place that has
        // to retract the flag.
        LocationSimulationSession.set(open: false)
    }
}

/// Lock-guarded mirror of the session state, readable from any thread.
///
/// Posts `.locationSimulationSessionEnded` on the main thread when either the
/// device session closes or the resend loop stops, so the app can defer a
/// tunnel rebuild until the single-occupancy RSD endpoint is free (review M4,
/// ported from TLocation's `locationSimulationSessionEnded`).
enum LocationSimulationSession {
    /// The app is no longer holding or maintaining a location-simulation
    /// session; observers may retry a deferred tunnel rebuild.
    static let sessionEndedNotification = Notification.Name.p2pLocationSimulationSessionEnded

    private static let lock = NSLock()
    private static var open = false
    private static var maintained = false

    static var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    static var isMaintained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return maintained
    }

    /// Called by the resend loop as it starts and stops.
    static func setMaintained(_ newValue: Bool) {
        lock.lock()
        let wasMaintained = maintained
        maintained = newValue
        lock.unlock()
        if wasMaintained && !newValue {
            postSessionEnded()
        }
    }

    fileprivate static func set(open newValue: Bool) {
        lock.lock()
        let wasOpen = open
        open = newValue
        lock.unlock()
        if wasOpen && !newValue {
            postSessionEnded()
        }
    }

    private static func postSessionEnded() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: sessionEndedNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: sessionEndedNotification, object: nil)
            }
        }
    }
}

/// The single serial queue every FFI location-simulation call runs on.
enum LocationSimulationCommandQueue {
    static let shared = DispatchQueue(label: "jp.haruki0420.p2pgps.location-sim", qos: .userInitiated)
}

// MARK: - Ported engine entry points

/// Starts (or updates) location simulation. Must run on
/// `LocationSimulationCommandQueue`.
func simulate_location(_ deviceIP: String, _ latitude: Double, _ longitude: Double, _ pairingFile: String) -> Int32 {
    if let locationSimulation = LocationSimulationState.locationSimulation {
        if let ffiError = location_simulation_set(locationSimulation, latitude, longitude) {
            // Not an error yet: the code below rebuilds the session from
            // scratch and either succeeds or logs why it did not.
            LogStore.shared.warning(
                "simulate_location: 既存セッションが更新を拒否 (\(IdeviceBridge.detail(from: ffiError)))。再構築します"
            )
            idevice_error_free(ffiError)
            LocationSimulationState.cleanup()
        } else {
            return LocationSimulationStatus.ok
        }
    }

    // The Remote Pairing service is advertised over Bonjour on recent iOS
    // versions; 49152 is only a fallback (StikDebug's RemotePairingPortResolver).
    let remotePairingPort = RemotePairingPortResolver.resolve(targetIPAddress: deviceIP)

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(remotePairingPort).bigEndian

    let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    guard inetResult == 1 else {
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.invalidIP)): “\(deviceIP)” は有効な IPv4 アドレスではありません。設定のターゲット IP を確認してください。"
        )
        return LocationSimulationStatus.invalidIP
    }

    var pairingHandle: OpaquePointer?
    let pairingError = pairingFile.withCString { rp_pairing_file_read($0, &pairingHandle) }
    if let pairingError {
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.pairingRead)): pairing file を読み取れません — \(IdeviceBridge.detail(from: pairingError))"
        )
        idevice_error_free(pairingError)
        return LocationSimulationStatus.pairingRead
    }

    guard let pairingHandle else {
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.pairingRead)): pairing file の読み取りが成功しましたがハンドルが返りませんでした"
        )
        return LocationSimulationStatus.pairingRead
    }

    defer { rp_pairing_file_free(pairingHandle) }

    let providerError = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            tunnel_create_rppairing(
                $0,
                socklen_t(MemoryLayout<sockaddr_in>.stride),
                "P2PGPSLocationSimulation",
                pairingHandle,
                nil,
                nil,
                &LocationSimulationState.adapter,
                &LocationSimulationState.handshake
            )
        }
    }

    if let providerError {
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.providerCreate)): \(deviceIP):\(remotePairingPort) へのトンネルを開けません — \(IdeviceBridge.detail(from: providerError))。LocalDevVPN が接続されているか確認してください。"
        )
        idevice_error_free(providerError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.providerCreate
    }

    let remoteServerError = remote_server_connect_rsd(
        LocationSimulationState.adapter,
        LocationSimulationState.handshake,
        &LocationSimulationState.remoteServer
    )
    if let remoteServerError {
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.remoteServer)): \(deviceIP):\(remotePairingPort) のリモートサービスに接続できません — \(IdeviceBridge.detail(from: remoteServerError))"
        )
        idevice_error_free(remoteServerError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.remoteServer
    }

    let locationSimulationError = location_simulation_new(
        LocationSimulationState.remoteServer,
        &LocationSimulationState.locationSimulation
    )
    if let locationSimulationError {
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.locationSimulation)): 位置シミュレーションセッションを開始できません — \(IdeviceBridge.detail(from: locationSimulationError))。Developer Disk Image がマウントされていない可能性があります。"
        )
        idevice_error_free(locationSimulationError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationSimulation
    }

    // The Rust implementation borrows the RemoteServerHandle
    // (`&mut (*server).0`) and does not take ownership of it. Keep the handle
    // and let cleanup() free it after the location-simulation handle, otherwise
    // every session leaks the remote-server socket.
    LocationSimulationSession.set(open: true)

    let locationSetError = location_simulation_set(
        LocationSimulationState.locationSimulation,
        latitude,
        longitude
    )
    if let locationSetError {
        // The coordinate is deliberately never written to the log.
        LogStore.shared.error(
            "simulate_location 失敗 (code \(LocationSimulationStatus.locationSet)): デバイスが座標を拒否しました — \(IdeviceBridge.detail(from: locationSetError))"
        )
        idevice_error_free(locationSetError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationSet
    }

    LogStore.shared.info("simulate_location: 新しいセッションで座標が受理されました")
    return LocationSimulationStatus.ok
}

/// How long the connection stack is held open after a successful clear, so the
/// device can actually act on it before the tunnel is torn down.
private let locationClearSettleInterval: TimeInterval = 0.3

/// Clears the simulated location. Must run on `LocationSimulationCommandQueue`.
func clear_simulated_location() -> Int32 {
    guard let locationSimulation = LocationSimulationState.locationSimulation else {
        // Not an error: `clear()` is always enqueued (review R-1), so "there is
        // no session to clear" is a normal outcome and must not spam the error
        // log (review R-16).
        LogStore.shared.info(
            "clear_simulated_location: セッションなし（成功扱い）"
        )
        return LocationSimulationStatus.locationClear
    }

    if let ffiError = location_simulation_clear(locationSimulation) {
        LogStore.shared.error(
            "clear_simulated_location 失敗 (code \(LocationSimulationStatus.locationClear)): デバイスがクリアを拒否しました — \(IdeviceBridge.detail(from: ffiError))"
        )
        idevice_error_free(ffiError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationClear
    }

    Thread.sleep(forTimeInterval: locationClearSettleInterval)
    LocationSimulationState.cleanup()

    LogStore.shared.info(
        "clear_simulated_location: クリアが受理されました（\(Int(locationClearSettleInterval * 1000)) ms 待機後にセッション終了）"
    )
    return LocationSimulationStatus.ok
}

// MARK: - Observable facade

/// Main-thread-observable wrapper around the ported engine.
///
/// The UI calls `set(latitude:longitude:)` / `clear()`; the engine serialises
/// the FFI calls, keeps the 5-second resend loop alive while a simulation is
/// active, and publishes the outcome for the Receiver screen and Diagnostics.
public final class LocationSimulationEngine: ObservableObject {
    public static let shared = LocationSimulationEngine()

    /// A simulation session is open on the device.
    @Published public private(set) var isSimulating = false
    /// The FFI currently holds a session handle.
    @Published public private(set) var sessionOpen = false
    /// An FFI call is in flight.
    @Published public private(set) var isWorking = false
    /// Last error, already phrased for the user.
    @Published public private(set) var lastError: String?
    /// When the current coordinate was last accepted.
    @Published public private(set) var lastSetAt: Date?
    /// The coordinate currently being simulated.
    @Published public private(set) var appliedLatitude: Double?
    @Published public private(set) var appliedLongitude: Double?
    /// Whether the DDI is mounted (refreshed by `refreshMountState()`).
    @Published public private(set) var isDeveloperDiskImageMounted = false

    /// Resend cadence (architecture §4 step 6: every 5 seconds).
    public var resendInterval: TimeInterval = 5

    private let queue = LocationSimulationCommandQueue.shared
    private var resendTimer: DispatchSourceTimer?
    private let log = LogStore.shared
    /// Monotonic token so a slow FFI call cannot clear `isWorking` for a newer
    /// request (review L-7) and so a queued stale `set` never runs after the
    /// user turned injection off (review R-1).
    ///
    /// Written on the main thread (`set` / `clear`), read from the serial FFI
    /// queue, so it is guarded by `generationLock`.
    private let generationLock = NSLock()
    private var operationGeneration = 0

    private init() {}

    private func beginOperation() -> Int {
        generationLock.lock()
        operationGeneration += 1
        let value = operationGeneration
        generationLock.unlock()
        return value
    }

    private var latestGeneration: Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return operationGeneration
    }

    // MARK: - Public API

    /// Starts simulating `latitude` / `longitude` and keeps it alive.
    ///
    /// The FFI call is only enqueued here; the published `isSimulating` flag
    /// flips on the main thread when it completes. Because `clear()` always
    /// enqueues its own FFI call, a queued `set` that has been superseded must
    /// not run at all — otherwise "injection ON → OFF immediately" would leave
    /// a device-side session behind (review R-1).
    public func set(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            lastError = "座標が不正です。緯度は ±90°、経度は ±180° の範囲で指定してください。"
            return
        }

        stopResendLoop()
        let generation = beginOperation()
        isWorking = true
        let targetIP = DeviceConnectionContext.targetIPAddress
        let pairingPath = PairingFileStore.prepareURLOnce().path

        queue.async { [weak self] in
            guard let self else { return }
            // Superseded while waiting in the queue (a newer set or a clear):
            // skip the FFI call entirely. The newest operation's completion is
            // responsible for `isWorking` / the published state.
            guard generation == self.latestGeneration else { return }

            let code = simulate_location(targetIP, latitude, longitude, pairingPath)
            DispatchQueue.main.async {
                guard generation == self.latestGeneration else { return }
                self.isWorking = false
                self.sessionOpen = LocationSimulationSession.isOpen
                if code == LocationSimulationStatus.ok {
                    self.isSimulating = true
                    self.lastError = nil
                    self.lastSetAt = Date()
                    self.appliedLatitude = latitude
                    self.appliedLongitude = longitude
                    self.startResendLoop(latitude: latitude, longitude: longitude)
                } else {
                    self.isSimulating = false
                    self.lastError = Self.message(for: code)
                    // The app's own tunnel is unusable after a handshake
                    // failure; drop it so the next foreground retry reconnects
                    // (review L-8).
                    if code == LocationSimulationStatus.providerCreate
                        || code == LocationSimulationStatus.remoteServer {
                        markTunnelDisconnected()
                    }
                }
            }
        }
    }

    /// Clears the simulated location and stops the resend loop.
    ///
    /// The FFI clear is **always** enqueued, even when the app believes there
    /// is no session: `set()` only enqueues its FFI call, so "injection ON →
    /// OFF immediately" would otherwise leave a device-side session behind
    /// (review R-1). A no-session `clear_simulated_location` is treated as
    /// success (review L-6).
    public func clear() {
        stopResendLoop()

        let generation = beginOperation()
        isWorking = true

        queue.async { [weak self] in
            guard let self else { return }
            // A newer set/clear supersedes this one; the newest operation owns
            // the device state and the published flags.
            guard generation == self.latestGeneration else { return }

            let code = clear_simulated_location()
            DispatchQueue.main.async {
                guard generation == self.latestGeneration else { return }
                self.isWorking = false
                self.isSimulating = false
                self.appliedLatitude = nil
                self.appliedLongitude = nil
                self.sessionOpen = LocationSimulationSession.isOpen
                if code == LocationSimulationStatus.ok
                    || code == LocationSimulationStatus.locationClear {
                    // 12 = "no session to clear"; not an error (review L-6).
                    self.lastError = nil
                } else {
                    self.lastError = Self.message(for: code)
                }
            }
        }
    }

    /// Stops the resend loop without touching the device session.
    public func pauseResending() {
        stopResendLoop()
    }

    /// Re-queries the DDI mount state on the serial FFI queue.
    public func refreshMountState() {
        queue.async { [weak self] in
            let mounted = isDDIMounted()
            DispatchQueue.main.async {
                self?.isDeveloperDiskImageMounted = mounted
            }
        }
    }

    // MARK: - Resend loop

    private func startResendLoop(latitude: Double, longitude: Double) {
        stopResendLoop()
        let targetIP = DeviceConnectionContext.targetIPAddress
        let pairingPath = PairingFileStore.prepareURLOnce().path
        let interval = max(resendInterval, 1)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let code = simulate_location(targetIP, latitude, longitude, pairingPath)
            if code != LocationSimulationStatus.ok {
                DispatchQueue.main.async {
                    self.sessionOpen = LocationSimulationSession.isOpen
                    self.isSimulating = self.sessionOpen
                    self.lastError = Self.message(for: code)
                    // A dead tunnel/session in the resend loop must be dropped
                    // just like a failed set(), otherwise the engine keeps
                    // claiming it is simulating and foreground retries are
                    // deferred forever.
                    if code == LocationSimulationStatus.providerCreate
                        || code == LocationSimulationStatus.remoteServer {
                        markTunnelDisconnected()
                    }
                }
            }
        }
        timer.resume()
        resendTimer = timer
        LocationSimulationSession.setMaintained(true)
    }

    private func stopResendLoop() {
        resendTimer?.cancel()
        resendTimer = nil
        LocationSimulationSession.setMaintained(false)
    }

    // MARK: - Error text

    /// Two-sentence recovery text for an upstream status code (DESIGN.md Copy).
    static func message(for code: Int32) -> String {
        switch code {
        case LocationSimulationStatus.invalidIP:
            return "ターゲット IP が不正です。設定で \(DeviceConnectionContext.defaultTargetIPAddress) に戻して再試行してください。"
        case LocationSimulationStatus.pairingRead:
            return "pairing file を読み取れません。設定から pairing file を読み込み直してください。"
        case LocationSimulationStatus.providerCreate:
            return "デバイスへのトンネルを作成できませんでした。LocalDevVPN が接続されているか確認して再試行してください。"
        case LocationSimulationStatus.remoteServer:
            return "デバイスのリモートサービスに接続できませんでした。Developer Mode と DDI の状態を確認して再試行してください。"
        case LocationSimulationStatus.locationSimulation:
            return "位置シミュレーションを開始できませんでした。設定で DDI をマウントしてから再試行してください。"
        case LocationSimulationStatus.locationSet:
            return "デバイスが座標を受け付けませんでした。少し待ってから再試行してください。"
        case LocationSimulationStatus.locationClear:
            return "位置シミュレーションを停止できませんでした。アプリを再起動して再試行してください。"
        default:
            return "位置シミュレーションに失敗しました。設定を確認して再試行してください。"
        }
    }
}
