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
//  Changes from upstream: alert presentation was replaced with a published
//  `lastError` string that the Settings screen renders inline.
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
    @Published public private(set) var mountingThread: Thread?
    @Published public private(set) var isDeveloperDiskImageMounted: Bool = false
    @Published public private(set) var lastError: String?

    private let log = LogStore.shared

    private init() {}

    /// Re-queries the device in the background.
    public func checkForMounted() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
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
    public func mountIfNeeded() {
        let currentlyMounted = isDDIMounted()
        isDeveloperDiskImageMounted = currentlyMounted

        guard isPairingFileReadable(), !currentlyMounted else {
            if currentlyMounted {
                log.info("DDI は既にマウント済みです")
            } else {
                log.warning("pairing file を読み取れないため DDI のマウントをスキップしました")
            }
            return
        }

        if let mountingThread {
            mountingThread.cancel()
            self.mountingThread = nil
        }

        let thread = Thread { [weak self] in
            guard let self else { return }
            self.log.info("DDI のマウントを開始しました")
            let mountError = mountPersonalDDI(
                imagePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path,
                trustcachePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path,
                manifestPath: URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path
            )

            DispatchQueue.main.async {
                if let mountError {
                    self.lastError = "DDI をマウントできませんでした。LocalDevVPN の接続と pairing file を確認して再試行してください。\n(\(mountError))"
                    self.log.error("DDI のマウントに失敗しました: \(mountError)")
                } else {
                    self.log.info("DDI をマウントしました")
                    self.isDeveloperDiskImageMounted = true
                    self.lastError = nil
                    self.checkForMounted()
                }
                self.mountingThread = nil
            }
        }

        thread.qualityOfService = .background
        thread.name = "p2pgps.ddi-mount"
        thread.start()
        mountingThread = thread
    }

    /// Whether the stored pairing file can be parsed by the FFI.
    public func isPairingFileReadable() -> Bool {
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
