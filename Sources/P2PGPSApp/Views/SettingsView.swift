//
//  SettingsView.swift
//  P2PGPSApp
//
//  P2P GPS — Settings (native Form, DESIGN.md "Settings / Diagnostics").
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSInjection
#endif

/// Opens the first URL that the system resolves, chaining through `open`'s
/// completion handler. A free function so the recursive step does not capture
/// the enclosing `View` value.
private func openFirstResolving(_ candidates: [URL]) {
    guard let next = candidates.first else { return }
    UIApplication.shared.open(next, options: [:]) { success in
        guard !success else { return }
        openFirstResolving(Array(candidates.dropFirst()))
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var mounting = MountingProgress.shared
    @ObservedObject private var tunnel = TunnelManager.shared

    @State private var isShowingPairingImporter = false
    @State private var pairingPresent = PairingFileStore.isPresent
    @State private var isDownloadingDDI = false
    @State private var ddiProgress: Double?
    @State private var ddiMessage: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let log = LogStore.shared

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                injectionSection
                receiverSection
                senderSection
                logSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(P2PColor.paper.ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isShowingPairingImporter,
                allowedContentTypes: PairingFileStore.supportedContentTypes
            ) { result in
                importPairingFile(result)
            }
            .onAppear {
                // iloader's "Place" writes into <App Documents>/pairingFile.plist;
                // pick it up when Settings opens (review: automatic placement).
                pairingPresent = PairingFileStore.importFromDocumentsIfPresent()
            }
        }
        .tint(P2PColor.pine)
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            Toggle("自動再接続", isOn: $settings.autoReconnect)

            HStack {
                Text("接続先（上級者向け）")
                Spacer()
                TextField(
                    DeviceConnectionContext.defaultTargetIPAddress,
                    text: $settings.targetDeviceIPAddress
                )
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(P2PFont.metric)
            }

            Button {
                TunnelManager.shared.start()
            } label: {
                Label("再接続", systemImage: "arrow.clockwise")
            }

            HStack {
                Text("iPad 内部への接続")
                Spacer()
                Text(tunnel.isConnected ? "接続済み" : (tunnel.isStarting ? "接続中…" : "未接続"))
                    .font(P2PFont.metric)
                    .foregroundStyle(tunnel.isConnected ? P2PColor.pine : P2PColor.inkSecondary)
            }

            if let tunnelError = tunnel.lastError {
                Text(tunnelError)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }
        } header: {
            Text("接続")
        } footer: {
            Text("通常は変更する必要はありません。うまく接続できないときだけ「再接続」を押してください。")
        }
    }

    private var injectionSection: some View {
        Section {
            HStack {
                Text("位置情報ファイル（pairing file）")
                Spacer()
                Text(pairingPresent ? "読み込み済み" : "未設定")
                    .font(P2PFont.metric)
                    .foregroundStyle(pairingPresent ? P2PColor.pine : P2PColor.inkSecondary)
            }

            Button {
                isShowingPairingImporter = true
            } label: {
                Label("pairing file を読み込む", systemImage: "doc.badge.plus")
            }

            Button {
                if PairingFileStore.importFromDocumentsIfPresent() {
                    pairingPresent = true
                    infoMessage = "アプリのフォルダに置かれた pairing file を読み込みました。"
                } else {
                    infoMessage = "アプリのフォルダに pairing file が見つかりません。"
                }
            } label: {
                Label("ファイルを選び直す", systemImage: "arrow.clockwise")
            }

            if pairingPresent {
                Button(role: .destructive) {
                    do {
                        try PairingFileStore.remove()
                        pairingPresent = false
                        infoMessage = "pairing file を削除しました。"
                    } catch {
                        errorMessage = "pairing file を削除できませんでした。\n(\(error.localizedDescription))"
                    }
                } label: {
                    Label("pairing file を削除", systemImage: "trash")
                }
            }

            HStack {
                Text("Developer Disk Image")
                Spacer()
                Text(mounting.isDeveloperDiskImageMounted ? "準備済み" : "未準備")
                    .font(P2PFont.metric)
                    .foregroundStyle(mounting.isDeveloperDiskImageMounted ? P2PColor.pine : P2PColor.inkSecondary)
            }

            Button {
                downloadDDI(force: false)
            } label: {
                Label(isDownloadingDDI ? "ダウンロード中…" : "DDI をダウンロード", systemImage: "arrow.down.circle")
            }
            .disabled(isDownloadingDDI)

            Button {
                downloadDDI(force: true)
            } label: {
                Label("DDI を再取得", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isDownloadingDDI)

            Button {
                MountingProgress.shared.mountIfNeeded()
            } label: {
                Label("DDI を使える状態にする", systemImage: "externaldrive.badge.checkmark")
            }

            if let ddiProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: ddiProgress)
                    Text(ddiMessage ?? "DDI をダウンロードしています…")
                        .font(P2PFont.caption)
                        .foregroundStyle(P2PColor.inkSecondary)
                }
            } else if let ddiMessage {
                Text(ddiMessage)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.inkSecondary)
            }

            if let mountingError = mounting.lastError {
                Text(mountingError)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }

            Button {
                openFirstResolving([
                    URL(string: "stosvpn://")!,
                    URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!,
                ])
            } label: {
                Label("LocalDevVPN を開く", systemImage: "network")
            }

            Toggle("TLocation に任せる（上級者向け）", isOn: $settings.useTLocationURLSchemeFallback)
        } header: {
            Text("位置の書き換え")
        } footer: {
            Text("この iPad の位置を書き換えるには、①位置情報ファイル、②Apple の開発用イメージ（DDI）、③LocalDevVPN の 3 つが必要です。下のボタンから順に準備してください。")
        }
    }

    private var receiverSection: some View {
        Section {
            Toggle("画面を消しても動かす（受信側）", isOn: $settings.keepAliveLocationUpdates)
        } header: {
            Text("受信（iPad）")
        } footer: {
            Text("iPad の画面を消しても位置の反映を続けるための設定です。位置情報の「常に許可」が必要です。")
        }
    }

    private var senderSection: some View {
        Section {
            Picker("送信間隔", selection: $settings.senderIntervalMilliseconds) {
                ForEach([UInt16(100), 500, 1_000, 2_000, 5_000], id: \.self) { value in
                    Text(P2PFormat.interval(value)).tag(value)
                }
            }

            Toggle("速度と向きも送る", isOn: $settings.extendedLocationEnabled)

            Button {
                settings.senderIntervalMilliseconds = 500
                settings.extendedLocationEnabled = true
            } label: {
                Label("高頻度更新（0.5 秒ごと）", systemImage: "bolt")
            }
        } header: {
            Text("送信（iPhone）")
        } footer: {
            Text("送信間隔は iPad 側からも変更できます。")
        }
    }

    private var logSection: some View {
        Section {
            Picker("座標の桁数", selection: $settings.logCoordinateDecimalPlaces) {
                ForEach([3, 5, 7], id: \.self) { value in
                    Text("\(value) 桁").tag(value)
                }
            }

            Button(role: .destructive) {
                log.clear()
                infoMessage = "ログを消去しました。"
            } label: {
                Label("ログを消去", systemImage: "trash")
            }
        } header: {
            Text("ログ")
        } footer: {
            Text("ログはメモリ内のみで、ディスクには保存しません。座標は指定した桁数に丸めて記録します。")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack {
                Text("バージョン")
                Spacer()
                Text(appVersion).font(P2PFont.metric)
            }
            HStack {
                Text("ライセンス")
                Spacer()
                Text("AGPL-3.0").font(P2PFont.metric)
            }
            Text("位置の書き換え機能は StikDebug / TLocation（AGPL-3.0）由来です。")
                .font(P2PFont.caption)
                .foregroundStyle(P2PColor.inkSecondary)
            Text("iPad 側は Developer Mode / LocalDevVPN / pairing file / DDI が必要です。")
                .font(P2PFont.caption)
                .foregroundStyle(P2PColor.inkSecondary)
        } header: {
            Text("このアプリ")
        }

        if let infoMessage {
            Section {
                Text(infoMessage)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.pine)
            }
        }

        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }
        }
    }

    // MARK: - Actions

    private func importPairingFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try PairingFileStore.importFromPicker(url)
                pairingPresent = true
                errorMessage = nil
                infoMessage = "pairing file を読み込みました。iPad 内部への接続をやり直します。"
                TunnelManager.shared.start()
            } catch {
                errorMessage = "pairing file を読み込めませんでした。ファイルを選び直してください。\n(\(error.localizedDescription))"
            }
        case .failure(let error):
            errorMessage = "pairing file を選択できませんでした。\n(\(error.localizedDescription))"
        }
    }

    private func downloadDDI(force: Bool) {
        guard !isDownloadingDDI else { return }
        isDownloadingDDI = true
        ddiProgress = 0
        ddiMessage = "ダウンロードを開始しています…"
        errorMessage = nil

        Task { @MainActor in
            do {
                if force {
                    try await DeveloperDiskImageService.shared.redownload { value, message in
                        DispatchQueue.main.async {
                            ddiProgress = value
                            ddiMessage = message
                        }
                    }
                } else {
                    try await DeveloperDiskImageService.shared.downloadMissingFiles()
                }
                isDownloadingDDI = false
                ddiProgress = nil
                ddiMessage = "DDI の準備ができました。使える状態にします。"
                MountingProgress.shared.mountIfNeeded()
            } catch {
                isDownloadingDDI = false
                ddiProgress = nil
                ddiMessage = nil
                errorMessage = "DDI をダウンロードできませんでした。ネットワーク接続を確認して再試行してください。\n(\(error.localizedDescription))"
            }
        }
    }
}
#endif
