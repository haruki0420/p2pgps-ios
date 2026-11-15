//
//  PairingFileStore.swift
//  P2PGPSInjection
//
//  P2P GPS — storage for the on-device pairing record.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Support/PairingFileStore.swift`), derived from StikDebug, AGPL-3.0.
//  Copyright (C) Stephen Bove and the StikDebug / TLocation contributors.
//
//  The pairing file is a secret. The canonical copy lives in Application
//  Support/Pairing with 0600 permissions, Data Protection (iOS), and the
//  "exclude from backup" flag. Documents is only a transient import location:
//  every migration path deletes the Documents copy afterwards, so the secret is
//  never stored twice (review M3).
//

import Foundation
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Stores the `.mobiledevicepairing` record used by the RSD tunnel.
public enum PairingFileStore {
    public static let fileName = "pairingFile.plist"
    public static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList,
    ]

    private static let legacyFileName = "rp_pairing_file.plist"
    private static let log = LogStore.shared

    /// Canonical location of the pairing file.
    public static var url: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    /// Whether a pairing file exists at the canonical location.
    public static var isPresent: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Makes sure the canonical file exists (migrating legacy copies) and
    /// returns its URL. The file may still not exist if the user never
    /// imported one.
    ///
    /// Any Documents copy is deleted after it has been migrated, and the
    /// canonical file is re-protected on every call. Prefer ``prepareURLOnce()``
    /// on hot paths (every fix / every resend) to avoid re-setting file
    /// attributes repeatedly (review R-7).
    @discardableResult
    public static func prepareURL(fileManager: FileManager = .default) -> URL {
        let destination = url
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        protectDirectory(fileManager: fileManager)

        if let documentURL = documentSourceURL(fileManager: fileManager) {
            if !fileManager.fileExists(atPath: destination.path) ||
                !fileManager.contentsEqual(atPath: documentURL.path, andPath: destination.path) {
                try? replaceItem(at: destination, with: documentURL, fileManager: fileManager)
            }
            protectPairingFile(at: destination, fileManager: fileManager)
            // The Documents copy is a transient import location only.
            removeDocumentsCopies(fileManager: fileManager)
            return destination
        }

        if !fileManager.fileExists(atPath: destination.path) {
            migrateLegacyCopy(to: destination, fileManager: fileManager)
        }
        protectPairingFile(at: destination, fileManager: fileManager)
        return destination
    }

    /// Cached variant of ``prepareURL(fileManager:)`` for hot paths.
    ///
    /// The full migration + protection pass runs on the first call, after
    /// ``replace(with:fileManager:)`` (new pairing file) and after
    /// ``remove(fileManager:)``. Everything in between is a lock + existence
    /// check, so the 1 Hz injection path does not re-apply 0600 / Data
    /// Protection / backup attributes on every fix (review R-7).
    @discardableResult
    public static func prepareURLOnce(fileManager: FileManager = .default) -> URL {
        cacheLock.lock()
        let cached = cachedURL
        cacheLock.unlock()

        if let cached, fileManager.fileExists(atPath: cached.path) {
            return cached
        }

        let prepared = prepareURL(fileManager: fileManager)
        cacheLock.lock()
        cachedURL = prepared
        cacheLock.unlock()
        return prepared
    }

    /// Replaces the stored pairing file with `sourceURL`.
    ///
    /// The file is copied straight into Application Support (never left in
    /// Documents), protected with 0600 / Data Protection / no-backup, and any
    /// legacy Documents copies are removed.
    public static func replace(with sourceURL: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        protectDirectory(fileManager: fileManager)

        try replaceItem(at: url, with: sourceURL, fileManager: fileManager)
        protectPairingFile(at: url, fileManager: fileManager)
        removeDocumentsCopies(fileManager: fileManager)
        invalidateCache()
    }

    /// Imports a pairing file chosen with the system document picker.
    public static func importFromPicker(_ sourceURL: URL, fileManager: FileManager = .default) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try replace(with: sourceURL, fileManager: fileManager)
    }

    /// Imports a pairing file that an external tool placed in the app's
    /// Documents directory, then moves it to the protected Application Support
    /// location.
    ///
    /// iloader's "Place" button writes the pairing file into
    /// `<App Documents>/pairingFile.plist` via House Arrest. This method picks
    /// that file up automatically (at launch / when the app becomes active /
    /// when Settings opens) so the user does not have to import it by hand.
    ///
    /// Returns `true` when a pairing file is present after the migration.
    @discardableResult
    public static func importFromDocumentsIfPresent(fileManager: FileManager = .default) -> Bool {
        guard documentSourceURL(fileManager: fileManager) != nil else {
            return isPresent
        }
        prepareURL(fileManager: fileManager)
        invalidateCache()
        let imported = isPresent
        if imported {
            log.info("Documents に置かれた pairing file を自動で読み込みました（iloader 等）")
        }
        return imported
    }

    /// Deletes the stored pairing file (and legacy copies).
    public static func remove(fileManager: FileManager = .default) throws {
        let destination = prepareURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        removeLegacyCopies(fileManager: fileManager)
        removeDocumentsCopies(fileManager: fileManager)
        invalidateCache()
    }

    // MARK: - Cache (review R-7)

    private static let cacheLock = NSLock()
    private static var cachedURL: URL?

    private static func invalidateCache() {
        cacheLock.lock()
        cachedURL = nil
        cacheLock.unlock()
    }

    // MARK: - Locations

    private static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    private static var legacyURLs: [URL] {
        [
            directoryURL.appendingPathComponent(legacyFileName),
            documentsURL,
            URL.documentsDirectory.appendingPathComponent(legacyFileName),
        ]
    }

    private static var documentsURL: URL {
        URL.documentsDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Migration

    private static func documentSourceURL(fileManager: FileManager) -> URL? {
        [documentsURL, URL.documentsDirectory.appendingPathComponent(legacyFileName)]
            .filter { fileManager.fileExists(atPath: $0.path) }
            .max {
                let firstDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let secondDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return firstDate < secondDate
            }
    }

    private static func migrateLegacyCopy(to destination: URL, fileManager: FileManager) {
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            do {
                try replaceItem(at: destination, with: legacyURL, fileManager: fileManager)
            } catch {
                if let data = try? Data(contentsOf: legacyURL) {
                    try? data.write(to: destination, options: .atomic)
                }
            }

            protectPairingFile(at: destination, fileManager: fileManager)
            break
        }
    }

    // MARK: - File operations

    private static func replaceItem(at destination: URL, with source: URL, fileManager: FileManager) throws {
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        defer { try? fileManager.removeItem(at: temporary) }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private static func removeLegacyCopies(fileManager: FileManager) {
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }

    /// Deletes the Documents copies left by older builds / imports.
    private static func removeDocumentsCopies(fileManager: FileManager) {
        for documentsCopy in [documentsURL, URL.documentsDirectory.appendingPathComponent(legacyFileName)] {
            guard fileManager.fileExists(atPath: documentsCopy.path) else { continue }
            do {
                try fileManager.removeItem(at: documentsCopy)
                log.info("Documents の pairing file コピーを削除しました")
            } catch {
                log.error("Documents の pairing file コピーを削除できませんでした: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Protection

    /// 0600 + Data Protection (iOS) + excluded from backup.
    private static func protectPairingFile(at url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            log.error("pairing file のパーミッションを 0600 に設定できませんでした: \(error.localizedDescription)")
        }

        #if os(iOS)
        do {
            // `.completeUntilFirstUserAuthentication` (not `.complete`): the
            // pairing file must be readable while the device is locked,
            // because the RSD session can be rebuilt in the background (review
            // R-2). `.complete` would make `rp_pairing_file_read` fail after a
            // lock and silently stop injection until the next unlock.
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            log.error("pairing file の Data Protection を設定できませんでした: \(error.localizedDescription)")
        }
        #endif

        excludeFromBackup(url, fileManager: fileManager)
    }

    private static func protectDirectory(fileManager: FileManager) {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        } catch {
            log.error("pairing ディレクトリのパーミッションを設定できませんでした: \(error.localizedDescription)")
        }
        excludeFromBackup(directoryURL, fileManager: fileManager)
    }

    private static func excludeFromBackup(_ url: URL, fileManager: FileManager) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            log.error("バックアップ除外フラグを設定できませんでした: \(error.localizedDescription)")
        }
    }
}
