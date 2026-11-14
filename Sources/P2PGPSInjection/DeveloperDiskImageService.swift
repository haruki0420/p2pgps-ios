//
//  DeveloperDiskImageService.swift
//  P2PGPSInjection
//
//  P2P GPS — downloads the personalized Developer Disk Image.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Ported from TLocation (https://github.com/truongkma/t-location,
//  commit 5e57f815e5958f133dfbaae8252473054adeccf0, file
//  `TLocation/Services/DeveloperDiskImageService.swift`), derived from StikDebug,
//  AGPL-3.0. Copyright (C) the StikDebug / TLocation contributors.
//
//  Changes from upstream (review M5 / L-11 / L-12):
//   * the download URLs are pinned to a fixed doronz88/DeveloperDiskImage
//     commit instead of `main`, so the bytes cannot change under us;
//   * every downloaded file is verified against a SHA-256 digest and deleted on
//     mismatch (supply-chain check);
//   * downloads land in a temporary file and are moved into place atomically,
//     and `redownload` only swaps the old files in after all three succeeded.
//

import CryptoKit
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Downloads and stores the personalized DDI files used to mount the developer
/// image on the device this app runs on.
public final class DeveloperDiskImageService {
    public static let shared = DeveloperDiskImageService()

    /// Pinned upstream commit of `doronz88/DeveloperDiskImage`.
    ///
    /// Do not point this at a branch: the DDI is code that runs on the device,
    /// so the exact bytes must be reproducible (review M5).
    public static let upstreamCommit = "a1020f81b6429f5ce40408cbe21c690512b613b5"

    private let fileManager: FileManager
    private let session: URLSession

    public init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    /// Downloads any DDI file that is missing or fails SHA-256 verification.
    public func downloadMissingFiles() async throws {
        for item in Self.downloadItems {
            let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            if fileManager.fileExists(atPath: destinationURL.path) {
                if (try? Self.sha256Hex(ofFileAt: destinationURL)) == item.sha256 {
                    continue
                }
                LogStore.shared.warning("DDI の SHA-256 が一致しないため再取得します: \(item.name)")
                try? fileManager.removeItem(at: destinationURL)
            }
            try await downloadFile(item: item, to: destinationURL)
        }
    }

    /// Downloads one DDI file, validating the URL scheme, HTTP status and
    /// SHA-256 digest, and replacing the destination atomically.
    private func downloadFile(item: DDIDownloadItem, to destinationURL: URL) async throws {
        guard let url = URL(string: item.urlString),
              url.scheme?.lowercased() == "https" else {
            LogStore.shared.error("DDI のダウンロード URL が不正です: \(item.urlString)")
            throw DDIDownloadError.invalidURL(item.urlString)
        }

        LogStore.shared.info("DDI のダウンロードを開始: \(item.name)")

        let (temporaryURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            LogStore.shared.error("DDI のダウンロードで HTTP 以外の応答を受信しました")
            throw DDIDownloadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            LogStore.shared.error("DDI のダウンロードが HTTP \(httpResponse.statusCode) で失敗しました")
            throw DDIDownloadError.badStatus(httpResponse.statusCode)
        }

        let actual = try Self.sha256Hex(ofFileAt: temporaryURL)
        guard actual.caseInsensitiveCompare(item.sha256) == .orderedSame else {
            try? fileManager.removeItem(at: temporaryURL)
            LogStore.shared.error("DDI の SHA-256 が一致しません: \(item.name) (actual \(actual))")
            throw DDIDownloadError.hashMismatch(expected: item.sha256, actual: actual)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try replaceAtomically(destination: destinationURL, with: temporaryURL)

        let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue
        let sizeText = size.map { String($0) } ?? "unknown"
        LogStore.shared.info("DDI のダウンロードが完了: \(item.name) (\(sizeText) bytes, SHA-256 OK)")
    }

    /// Deletes every DDI file and downloads them again.
    ///
    /// All three files are downloaded to temporary names first; the existing
    /// files are only replaced once every download has passed verification
    /// (review L-11).
    public func redownload(progressHandler: ((Double, String) -> Void)? = nil) async throws {
        let totalStages = Double(Self.downloadItems.count + 1)
        var completedStages = 0.0

        LogStore.shared.info("DDI の再取得を開始します")
        progressHandler?(0.0, "DDI を再取得しています…")

        var staged: [(item: DDIDownloadItem, temporary: URL)] = []
        defer {
            for entry in staged {
                try? fileManager.removeItem(at: entry.temporary)
            }
        }

        for item in Self.downloadItems {
            progressHandler?(completedStages / totalStages, "\(item.name) をダウンロードしています…")
            let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            let temporaryURL = destinationURL.appendingPathExtension("download")
            try? fileManager.removeItem(at: temporaryURL)
            try await downloadFile(item: item, to: temporaryURL)
            staged.append((item: item, temporary: temporaryURL))
            completedStages += 1.0
            progressHandler?(completedStages / totalStages, "\(item.name) を検証しました")
        }

        for entry in staged {
            let destinationURL = URL.documentsDirectory.appendingPathComponent(entry.item.relativePath)
            try replaceAtomically(destination: destinationURL, with: entry.temporary)
        }

        LogStore.shared.info("DDI の再取得が完了しました")
        progressHandler?(1.0, "DDI のダウンロードが完了しました。")
    }

    /// Whether all three DDI files exist locally.
    public var isDownloaded: Bool {
        Self.downloadItems.allSatisfy { item in
            fileManager.fileExists(
                atPath: URL.documentsDirectory.appendingPathComponent(item.relativePath).path
            )
        }
    }

    // MARK: - Helpers

    private func replaceAtomically(destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    /// Streaming SHA-256 (the DDI image is large enough that loading it into
    /// memory just to hash it would be wasteful).
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Download list

    private static let upstreamBaseURL =
        "https://github.com/doronz88/DeveloperDiskImage/raw/\(upstreamCommit)/PersonalizedImages/Xcode_iOS_DDI_Personalized"

    static let downloadItems: [DDIDownloadItem] = [
        .init(
            name: "BuildManifest.plist",
            relativePath: "DDI/BuildManifest.plist",
            urlString: "\(upstreamBaseURL)/BuildManifest.plist",
            sha256: "3C4EEE2BE4A0A853044DC32DBBD62699302B1DFD317AAF4F1CF36368B7639BB0"
        ),
        .init(
            name: "Image.dmg",
            relativePath: "DDI/Image.dmg",
            urlString: "\(upstreamBaseURL)/Image.dmg",
            sha256: "0DE55B0CCDE9D5790C9C9F4E1A413225443FCE7EA75ACB503ACA11E7D8156646"
        ),
        .init(
            name: "Image.dmg.trustcache",
            relativePath: "DDI/Image.dmg.trustcache",
            urlString: "\(upstreamBaseURL)/Image.dmg.trustcache",
            sha256: "F0FB56DA2829F69B8AAE113584349635738E68D77C82A726ED72040890F16BF4"
        ),
    ]
}

/// One file of the personalized DDI package.
struct DDIDownloadItem: Sendable {
    let name: String
    let relativePath: String
    let urlString: String
    let sha256: String
}

/// Errors surfaced by the DDI downloader.
public enum DDIDownloadError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case badStatus(Int)
    case hashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let string):
            return "ダウンロード URL が不正です: \(string)"
        case .invalidResponse:
            return "DDI サーバーから不正な応答が返りました。"
        case .badStatus(let statusCode):
            return "DDI サーバーが HTTP \(statusCode) を返しました。"
        case .hashMismatch(let expected, let actual):
            return "DDI の SHA-256 が一致しません（期待 \(expected) / 実際 \(actual)）。ファイルを削除しました。"
        }
    }
}
