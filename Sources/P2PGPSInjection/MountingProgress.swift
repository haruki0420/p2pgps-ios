//
//  MountingProgress.swift
//  P2PGPSInjection
//
//  P2P GPS — Developer Disk Image mount progress and state.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Device/MountingProgress.swift`), derived from StikDebug, AGPL-3.0.
//  Copyright (C) Stephen Bove and the StikDebug / TLocation contributors.
//
//  Changes from upstream (review M4):
//   * every FFI call (mount check, pairing read, mount itself) runs on the
//     single serial `LocationSimulationCommandQueue` instead of the main thread
//     or an ad-hoc `Thread`, so a mount can never race the location simulation's
//     own RSD handshake;
//   * the `Thread` handle is replaced by a published `isMounting` flag.
//

import Combine
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif
import idevice

/// Tracks the mount state of the personal Developer Disk Image.
public final class MountingProgress: ObservableObject {
    public static let shared = MountingProgress()

    @Published public private(set) var mountProgress: Double = 0
    @Published public private(set) var isMounting = false
    @Published public private(set) var isDeveloperDiskImageMounted: Bool = false
    @Published public private(set) var lastError: String?

    private let queue = LocationSimulationCommandQueue.shared
    private let log = LogStore.shared

    private init() {}

    /// Re-queries the device on the serial FFI queue.
    public func checkForMounted() {
        queue.async { [weak self] in
            let mounted = isDDIMounted()
            DispatchQueue.main.async {
                self?.isDeveloperDiskImageMounted = mounted
            }
        }
    }

    /// Called from the FFI progress callback; hops to the main thread.
    public func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
        guard total > 0 else { return }
        let percentage = Double(progress) / Double(total) * 100.0
        DispatchQueue.main.async { [weak self] in
            self?.mountProgress = percentage
        }
    }

    /// Mounts the DDI if a pairing file exists and nothing is mounted yet.
    ///
    /// The whole FFI sequence (mount check → pairing read → mount) is appended
    /// to `LocationSimulationCommandQueue`, so it is serialised with the
    /// location-simulation calls that use the same single-occupancy RSD
    /// endpoint. Results are published on the main thread.
    public func mountIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isMounting else { return }
            self.isMounting = true
            self.lastError = nil

            self.queue.async { [weak self] in
                guard let self else { return }
                let mounted = isDDIMounted()
                let pairingReadable = self.isPairingFileReadableOnQueue()

                var mountError: String?
                var mountedNow = mounted
                if mounted {
                    self.log.info("DDI は既にマウント済みです")
                } else if !pairingReadable {
                    self.log.warning("pairing file を読み取れないため DDI のマウントをスキップしました")
                } else {
                    self.log.info("DDI のマウントを開始しました")
                    mountError = mountPersonalDDI(
                        imagePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path,
                        trustcachePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path,
                        manifestPath: URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path
                    )
                    mountedNow = mountError == nil
                }

                DispatchQueue.main.async {
                    self.isMounting = false
                    self.isDeveloperDiskImageMounted = mountedNow
                    if let mountError {
                        self.lastError = "DDI をマウントできませんでした。LocalDevVPN の接続と pairing file を確認して再試行してください。\n(\(mountError))"
                        self.log.error("DDI のマウントに失敗しました: \(mountError)")
                    } else if !mounted && pairingReadable {
                        self.log.info("DDI をマウントしました")
                        self.checkForMounted()
                    }
                }
            }
        }
    }

    /// Whether the stored pairing file can be parsed by the FFI.
    ///
    /// Must only be called on `LocationSimulationCommandQueue`.
    private func isPairingFileReadableOnQueue() -> Bool {
        let pairingPath = PairingFileStore.prepareURL().path
        var pairingFile: OpaquePointer?
        let error = rp_pairing_file_read(pairingPath, &pairingFile)
        if error != nil {
            if let error {
                idevice_error_free(error)
            }
            return false
        }
        rp_pairing_file_free(pairingFile)
        return true
    }
}
