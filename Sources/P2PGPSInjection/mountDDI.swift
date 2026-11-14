//
//  mountDDI.swift
//  P2PGPSInjection
//
//  P2P GPS — Developer Disk Image mount helpers.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Device/mountDDI.swift`), derived from StikDebug, AGPL-3.0.
//  Copyright (C) Stossy11 and the StikDebug / TLocation contributors.
//
//  Changes from upstream: alert presentation was removed (the app observes
//  `MountingProgress.lastError`), and the mount-check helpers were renamed so
//  they cannot be confused with the `MountingProgress` properties.
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif
import idevice

/// Progress callback handed to `image_mounter_mount_personalized_with_callback_rsd`.
func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
    MountingProgress.shared.progressCallback(progress: progress, total: total, context: context)
}

/// Result of asking the device whether a developer disk image is mounted.
enum MountCheckResult {
    case mounted
    case notMounted
    /// The tunnel / pairing file is not usable right now, so the question
    /// cannot be answered.
    case unreachable
}

/// Whether a developer disk image is currently mounted.
func isDDIMounted() -> Bool {
    checkDDIMountStatus() == .mounted
}

/// Queries the image mounter for the number of mounted images.
func checkDDIMountStatus() -> MountCheckResult {
    do {
        let result = try JITEnableContext.shared.getMountedDeviceCount()
        return result > 0 ? .mounted : .notMounted
    } catch {
        return .unreachable
    }
}

/// Mounts a personalized DDI. Returns `nil` on success, or a message on failure.
func mountPersonalDDI(imagePath: String, trustcachePath: String, manifestPath: String) -> String? {
    do {
        try JITEnableContext.shared.mountPersonalDDI(
            withImagePath: imagePath,
            trustcachePath: trustcachePath,
            manifestPath: manifestPath
        )
    } catch {
        LogStore.shared.error("DDI のマウントに失敗しました: \(error.localizedDescription)")
        return error.localizedDescription
    }
    return nil
}
