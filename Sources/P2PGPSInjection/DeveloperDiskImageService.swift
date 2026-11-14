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
//  Changes from upstream: localized string lookups were replaced with plain
//  Japanese text (this app ships a single language).
//

import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

/// Downloads and stores the personalized DDI files used to mount the developer
/// image on the device this app runs on.
public final class DeveloperDiskImageService {
    public static let shared = DeveloperDiskImageService()

    private let fileManager: FileManager
    private let session: URLSession

    public init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    /// Downloads any DDI file that is missing from Documents/DDI.
    public func downloadMissingFiles() async throws {
        for item in Self.downloadItems {
            let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }
            try await downloadFile(from: item.urlString, to: destinationURL)
        }
    }

    /// Downloads one file, validating the URL scheme and HTTP status.
    public func downloadFile(from urlString: String, to destinationURL: URL) async throws {
        let fileName = destinationURL.lastPathComponent

        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else {
            LogStore.shared.error("DDI のダウンロード URL が不正です: \(urlString)")
            throw DDIDownloadError.invalidURL(urlString)
        }

        LogStore.shared.info("DDI のダウンロードを開始: \(fileName)")

        let (temporaryURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            LogStore.shared.error("DDI のダウンロードで HTTP 以外の応答を受信しました")
            throw DDIDownloadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            LogStore.shared.error("DDI のダウンロードが HTTP \(httpResponse.statusCode) で失敗しました")
            throw DDIDownloadError.badStatus(httpResponse.statusCode)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
        let size = (attributes?[.size] as? Int).map(String.init) ?? "unknown"
        LogStore.shared.info("DDI のダウンロードが完了: \(fileName) (\(size) bytes)")
    }

    /// Deletes every DDI file and downloads them again.
    public func redownload(progressHandler: ((Double, String) -> Void)? = nil) async throws {
        let totalStages = Double(Self.downloadItems.count + 1)
        var completedStages = 0.0

        LogStore.shared.info("DDI の再取得を開始します（既存ファイルを削除）")
        progressHandler?(0.0, "既存の DDI ファイルを削除しています…")
        for item in Self.downloadItems {
            let fileURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        completedStages += 1.0
        progressHandler?(completedStages / totalStages, "ダウンロードを開始しています…")

        for item in Self.downloadItems {
            let name = item.name
            progressHandler?(completedStages / totalStages, "\(name) をダウンロードしています…")
            let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            try await downloadFile(from: item.urlString, to: destinationURL)
            completedStages += 1.0
            progressHandler?(completedStages / totalStages, "\(name) の準備ができました")
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

    private static let downloadItems: [DDIDownloadItem] = [
        .init(
            name: "BuildManifest.plist",
            relativePath: "DDI/BuildManifest.plist",
            urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/BuildManifest.plist"
        ),
        .init(
            name: "Image.dmg",
            relativePath: "DDI/Image.dmg",
            urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg"
        ),
        .init(
            name: "Image.dmg.trustcache",
            relativePath: "DDI/Image.dmg.trustcache",
            urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache"
        ),
    ]
}

private struct DDIDownloadItem {
    let name: String
    let relativePath: String
    let urlString: String
}

/// Errors surfaced by the DDI downloader.
public enum DDIDownloadError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let string):
            return "ダウンロード URL が不正です: \(string)"
        case .invalidResponse:
            return "DDI サーバーから不正な応答が返りました。"
        case .badStatus(let statusCode):
            return "DDI サーバーが HTTP \(statusCode) を返しました。"
        }
    }
}
