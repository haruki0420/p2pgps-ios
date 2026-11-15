//
//  JITEnableContext.swift
//  P2PGPSInjection
//
//  P2P GPS — RSD tunnel to the device this app is running on.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Device/JITEnableContext.swift`), derived from StikDebug
//  (https://github.com/StikDebug/StikDebug), AGPL-3.0.
//  Copyright (C) Stephen Bove and the StikDebug / TLocation contributors.
//
//  Changes from upstream: the class is internal to this module (the app talks to
//  `TunnelManager` instead), and the error domain was renamed. The tunnel
//  creation logic is unchanged.
//

import Darwin
import Foundation
import idevice
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Owns the app's long-lived RSD tunnel to `<targetIP>:<discovered RSD port>`.
///
/// This tunnel is used for DDI mounting and mount checks. The port is
/// discovered over Bonjour (`_remotepairing._tcp`) because recent iOS versions
/// do not guarantee the historical fixed port 49152 (see
/// `RemotePairingPortResolver`).
final class JITEnableContext {
    static let shared = JITEnableContext()

    private struct TunnelHandles {
        var adapter: OpaquePointer?
        var handshake: OpaquePointer?

        mutating func free() {
            if let handshake {
                rsd_handshake_free(handshake)
                self.handshake = nil
            }
            if let adapter {
                adapter_free(adapter)
                self.adapter = nil
            }
        }
    }

    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?

    private let tunnelLock = NSLock()
    private var tunnelConnecting = false
    private var tunnelSemaphore: DispatchSemaphore?
    private var lastTunnelError: NSError?

    var adapterHandle: OpaquePointer? { adapter }
    var handshakeHandle: OpaquePointer? { handshake }

    private init() {
        // The FFI logger is initialised with both sinks disabled.
        //
        // Writing `idevice_log.txt` into Documents would leave a permanent,
        // plain-text record of every device interaction in the Files app,
        // readable by anyone holding the device and captured by every backup.
        // For an app whose users are deliberately choosing where they appear,
        // that is the worst possible place to keep a log. Every error the app
        // shows is read from the `IdeviceFfiError` struct instead (see
        // `IdeviceBridge.detail`), never from this logger.
        //
        // The call is kept so the library's global logger is initialised exactly
        // once, with a valid non-NULL path as `idevice.h` requires. The path
        // points at a Caches subdirectory that is never created, so even a build
        // that ignored `Disabled` could not write into Documents.
        let unusedLogURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("idevice-ffi-logging-disabled.log")

        var path = Array(unusedLogURL.path.utf8CString)
        path.withUnsafeMutableBufferPointer { buffer in
            _ = idevice_init_logger(Disabled, Disabled, buffer.baseAddress)
        }
    }

    deinit {
        if let handshake {
            rsd_handshake_free(handshake)
        }
        if let adapter {
            adapter_free(adapter)
        }
    }

    private func makeError(_ message: String, code: Int = -1) -> NSError {
        NSError(
            domain: "P2PGPS",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func nsString(from cString: UnsafePointer<CChar>?, fallback: String) -> String {
        guard let cString, let string = String(validatingUTF8: cString) else {
            return fallback
        }
        return string
    }

    private func error(from ffiError: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) -> NSError {
        guard let ffiError else {
            return makeError(fallback)
        }
        let message = nsString(from: ffiError.pointee.message, fallback: fallback)
        let error = makeError(message, code: Int(ffiError.pointee.code))
        idevice_error_free(ffiError)
        return error
    }

    private func getPairingFile() throws -> OpaquePointer {
        let pairingFileURL = PairingFileStore.prepareURLOnce()

        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            throw makeError("Pairing file not found!", code: -17)
        }

        var pairingFile: OpaquePointer?
        let ffiError = pairingFileURL.path.withCString { path in
            rp_pairing_file_read(path, &pairingFile)
        }

        if let ffiError {
            throw error(from: ffiError, fallback: "Failed to read pairing file!")
        }

        guard let pairingFile else {
            throw makeError("Failed to read pairing file!", code: -17)
        }

        return pairingFile
    }

    private func createTunnel(hostname: String) throws -> TunnelHandles {
        let pairingFile = try getPairingFile()
        defer { rp_pairing_file_free(pairingFile) }

        let deviceIP = DeviceConnectionContext.targetIPAddress
        let remotePairingPort = RemotePairingPortResolver.resolve(targetIPAddress: deviceIP)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(remotePairingPort).bigEndian

        let parseResult = deviceIP.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard parseResult == 1 else {
            throw makeError("Failed to parse target IP address.", code: -18)
        }

        var tunnel = TunnelHandles()
        let ffiError = hostname.withCString { hostname in
            withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing(
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                        hostname,
                        pairingFile,
                        nil,
                        nil,
                        &tunnel.adapter,
                        &tunnel.handshake
                    )
                }
            }
        }

        if let ffiError {
            throw error(from: ffiError, fallback: "Failed to create tunnel")
        }

        guard tunnel.adapter != nil, tunnel.handshake != nil else {
            var incompleteTunnel = tunnel
            incompleteTunnel.free()
            throw makeError("Tunnel was created without valid handles")
        }

        // `tunnel_create_rppairing` may update the pairing file in place
        // (pair-setup). Persist the handle so the next session does not have to
        // pair again; a write failure is not fatal for this tunnel.
        let pairingPath = PairingFileStore.prepareURLOnce().path
        if let writeError = rp_pairing_file_write(pairingFile, pairingPath) {
            LogStore.shared.warning(
                "pairing file の更新を保存できませんでした: \(IdeviceBridge.detail(from: writeError))"
            )
            idevice_error_free(writeError)
        }

        return tunnel
    }

    func startTunnel() throws {
        tunnelLock.lock()
        if tunnelConnecting {
            let waitSemaphore = tunnelSemaphore
            tunnelLock.unlock()

            if let waitSemaphore {
                waitSemaphore.wait()
                waitSemaphore.signal()
            }

            if let lastTunnelError {
                throw lastTunnelError
            }
            return
        }

        tunnelConnecting = true
        let completionSemaphore = DispatchSemaphore(value: 0)
        tunnelSemaphore = completionSemaphore
        tunnelLock.unlock()

        var newAdapter: OpaquePointer?
        var newHandshake: OpaquePointer?
        var finalError: NSError?

        defer {
            tunnelLock.lock()
            tunnelConnecting = false
            tunnelSemaphore = nil
            lastTunnelError = finalError
            tunnelLock.unlock()
            completionSemaphore.signal()
        }

        do {
            let newTunnel = try createTunnel(hostname: "P2PGPS")
            newAdapter = newTunnel.adapter
            newHandshake = newTunnel.handshake
        } catch let tunnelError as NSError {
            finalError = tunnelError
            throw tunnelError
        }

        if let handshake {
            rsd_handshake_free(handshake)
        }
        if let adapter {
            adapter_free(adapter)
        }

        adapter = newAdapter
        handshake = newHandshake
    }

    /// Frees the cached tunnel handles so the next `ensureTunnel()` reconnects.
    ///
    /// Must be called on `LocationSimulationCommandQueue`, the same serial
    /// context as every other FFI call. Used by `TunnelManager.markDisconnected`
    /// so a failed/stale tunnel is not reused forever (review L-9).
    func invalidateTunnel() {
        tunnelLock.lock()
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
        lastTunnelError = nil
        tunnelLock.unlock()
    }

    func ensureTunnel() throws {
        if adapter == nil || handshake == nil {
            try startTunnel()
        }
    }
}
