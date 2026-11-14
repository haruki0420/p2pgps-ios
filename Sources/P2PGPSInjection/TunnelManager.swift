//
//  TunnelManager.swift
//  P2PGPSInjection
//
//  P2P GPS — owns the app's RSD tunnel lifecycle.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Services/TunnelManager.swift`), derived from StikDebug, AGPL-3.0.
//  Copyright (C) the StikDebug / TLocation contributors.
//
//  Changes from upstream (review M4 / L-8 / L-9):
//   * tunnel creation runs on the single serial `LocationSimulationCommandQueue`
//     instead of a global queue, so it can never race the location simulation's
//     own RSD handshake against the single-occupancy endpoint;
//   * `markDisconnected()` invalidates the cached FFI handles so the next
//     `ensureTunnel()` really retries instead of reusing a stale tunnel;
//   * alert presentation was replaced with a published `lastError`.
//

import Combine
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Owns the app's long-lived tunnel used for DDI mounting.
public final class TunnelManager: ObservableObject {
    public static let shared = TunnelManager()

    @Published public private(set) var isConnected = false
    @Published public private(set) var isStarting = false
    @Published public private(set) var lastError: String?

    private let queue = LocationSimulationCommandQueue.shared
    private let log = LogStore.shared

    private init() {}

    /// Marks the tunnel as gone (e.g. after the VPN dropped or a failed start)
    /// and drops the cached FFI handles so the next start retries.
    public func markDisconnected() {
        queue.async {
            JITEnableContext.shared.invalidateTunnel()
        }
        runOnMain {
            self.isConnected = false
        }
    }

    /// Starts the tunnel if a pairing file exists. Safe to call repeatedly.
    ///
    /// The FFI handshake is serialised on `LocationSimulationCommandQueue`;
    /// only the cheap pairing-file existence check and the published-state
    /// updates happen on the main thread.
    public func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start() }
            return
        }

        let pairingFileURL = PairingFileStore.prepareURLOnce()
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            isConnected = false
            lastError = "pairing file がありません。設定から pairing file を読み込んでください。"
            log.warning("トンネル開始をスキップ: pairing file が未設定")
            return
        }

        guard !isStarting else { return }

        isStarting = true
        lastError = nil

        queue.async { [weak self] in
            let result: Result<Void, NSError>
            do {
                try JITEnableContext.shared.startTunnel()
                result = .success(())
            } catch {
                result = .failure(error as NSError)
            }

            DispatchQueue.main.async {
                self?.finishStart(result)
            }
        }
    }

    private func finishStart(_ result: Result<Void, NSError>) {
        isStarting = false

        switch result {
        case .success:
            isConnected = true
            lastError = nil
            log.info("トンネル接続に成功しました (\(DeviceConnectionContext.targetIPAddress):49152)")
            mountDeveloperDiskImageIfNeeded()
        case .failure(let error):
            isConnected = false
            lastError = Self.recoveryMessage(for: error)
            log.error("トンネル接続に失敗しました: \(error.localizedDescription) (code \(error.code))")
            // Drop any stale handles so the next attempt really reconnects.
            queue.async {
                JITEnableContext.shared.invalidateTunnel()
            }
        }
    }

    private func mountDeveloperDiskImageIfNeeded() {
        let trustcachePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path
        guard FileManager.default.fileExists(atPath: trustcachePath),
              !MountingProgress.shared.isDeveloperDiskImageMounted,
              !MountingProgress.shared.isMounting else {
            return
        }
        MountingProgress.shared.mountIfNeeded()
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Two-sentence recovery text (what happened + what to do), per DESIGN.md.
    static func recoveryMessage(for error: NSError) -> String {
        let target = DeviceConnectionContext.targetIPAddress
        let raw = error.localizedDescription.lowercased()

        if error.code == -9 {
            return "pairing file が無効か期限切れです。設定から新しい pairing file を読み込んでください。"
        }
        if error.code == 48 || raw.contains("address already in use") || raw.contains("port already in use") {
            return "接続に必要なポートが使用中です。他の VPN / デバッグアプリを閉じて LocalDevVPN を再接続し、再試行してください。"
        }
        if error.code == -18 || raw.contains("parse target ip") {
            return "ターゲット IP が不正です。設定で \(DeviceConnectionContext.defaultTargetIPAddress) に戻して再試行してください。"
        }
        if raw.contains("timed out") || raw.contains("timeout") {
            return "接続がタイムアウトしました。Wi-Fi と LocalDevVPN が接続されているか確認して再試行してください。"
        }
        if raw.contains("network is unreachable") || raw.contains("no route") {
            return "VPN の経路がありません。LocalDevVPN を接続し直してから再試行してください。"
        }
        return "\(target):49152 に接続できませんでした。Wi-Fi と LocalDevVPN を確認し、pairing file を選び直して再試行してください。"
    }
}

/// Starts the tunnel in the background (convenience for views).
public func startTunnelInBackground() {
    TunnelManager.shared.start()
}

/// Starts the tunnel only after any in-flight location-simulation command.
///
/// The RSD endpoint is single-occupancy (see `TunnelManager` docs and the errno
/// 48 recovery text), so a tunnel rebuild must not race the simulation's own
/// handshake. Appending to the serial command queue means the start waits its
/// turn; it is deferred, never refused.
public func startTunnelAfterPendingLocationCommands() {
    LocationSimulationCommandQueue.shared.async {
        DispatchQueue.main.async {
            startTunnelInBackground()
        }
    }
}

/// Marks the tunnel as disconnected and invalidates the cached FFI handles.
public func markTunnelDisconnected() {
    TunnelManager.shared.markDisconnected()
}
