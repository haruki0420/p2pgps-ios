//
//  ConnectionDiagnostics.swift
//  P2PGPSApp
//
//  P2P GPS — on-device connection diagnostics.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Explains *why* the RSD tunnel cannot be established without needing a Mac:
//  pairing-file format, Wi-Fi path, and TCP reachability of the target.
//  The VPN itself cannot be inspected from a sandboxed app, so the UI also
//  points at the manual checks (LocalDevVPN connected / Developer Mode).
//

#if canImport(UIKit)
import Foundation
import Network
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSInjection
#endif

struct ConnectionDiagnosticResult: Identifiable {
    enum Status {
        case ok
        case warning
        case failure
        case info
    }

    let id = UUID()
    let title: String
    let status: Status
    let detail: String
}

@MainActor
final class ConnectionDiagnostics: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var results: [ConnectionDiagnosticResult] = []
    @Published private(set) var summary: String?

    private let targetHost = DeviceConnectionContext.targetIPAddress

    func run() {
        guard !isRunning else { return }
        isRunning = true
        results = []
        summary = nil

        Task { [weak self] in
            guard let self else { return }

            var collected: [ConnectionDiagnosticResult] = []
            collected.append(
                ConnectionDiagnosticResult(
                    title: "iOS",
                    status: .info,
                    detail: ProcessInfo.processInfo.operatingSystemVersionString
                )
            )
            collected.append(self.pairingFileResult())

            let wifi = await self.wifiResult()
            collected.append(wifi)

            // Bonjour discovery can block for a few seconds; keep it off the
            // main actor.
            let port = await Task.detached {
                RemotePairingPortResolver.resolve(targetIPAddress: DeviceConnectionContext.targetIPAddress)
            }.value
            collected.append(
                ConnectionDiagnosticResult(
                    title: "Remote Pairing ポート",
                    status: .info,
                    detail: RemotePairingPortResolver.lastAttemptDescription
                )
            )

            let tcp = await self.tcpResult(port: port)
            collected.append(tcp)

            collected.append(
                ConnectionDiagnosticResult(
                    title: "VPN",
                    status: .info,
                    detail: "アプリからは他の VPN の状態を確認できません。設定 > VPN で LocalDevVPN が「接続済み」になっているか、他の VPN（Tailscale・DNS ブロッカー等）が有効になっていないか確認してください。iOS で同時に使える VPN は 1 つだけです。"
                )
            )
            collected.append(
                ConnectionDiagnosticResult(
                    title: "Developer Mode / Wi-Fi",
                    status: .info,
                    detail: "Remote Pairing サービスは Wi-Fi 接続中かつ Developer Mode が ON のときだけ開きます。設定 > プライバシーとセキュリティ > デベロッパモード、および Wi-Fi の接続を確認してください。"
                )
            )
            collected.append(
                ConnectionDiagnosticResult(
                    title: "ローカルネットワーク",
                    status: .info,
                    detail: "Remote Pairing のポートは Bonjour（`_remotepairing._tcp`）で自動検出します。初回に「ローカルネットワーク」の許可を求められたら許可してください（設定 > プライバシーとセキュリティ > ローカルネットワーク）。拒否するとポート検出に失敗し、49152 へのフォールバックになります。"
                )
            )

            self.results = collected
            self.isRunning = false
            self.summary = self.makeSummary(collected)
        }
    }

    // MARK: - Checks

    private func pairingFileResult() -> ConnectionDiagnosticResult {
        guard PairingFileStore.isPresent else {
            return ConnectionDiagnosticResult(
                title: "pairing file",
                status: .failure,
                detail: "pairing file がありません。設定から読み込んでください。"
            )
        }

        let url = PairingFileStore.url
        guard let data = try? Data(contentsOf: url) else {
            return ConnectionDiagnosticResult(
                title: "pairing file",
                status: .failure,
                detail: "pairing file を読み込めませんでした（破損・権限の問題）。"
            )
        }
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return ConnectionDiagnosticResult(
                title: "pairing file",
                status: .failure,
                detail: "pairing file が plist として読めません。iloader などでエクスポートし直してください。"
            )
        }

        let hasRPPairing =
            (plist["public_key"] as? Data)?.count == 32
            && (plist["private_key"] as? Data)?.count == 32
            && plist["identifier"] is String
        let hasLockdown =
            plist["DeviceCertificate"] != nil
            || plist["HostCertificate"] != nil
            || plist["RootCertificate"] != nil

        if hasRPPairing {
            let suffix = hasLockdown ? "（lockdown 情報も含む）" : ""
            return ConnectionDiagnosticResult(
                title: "pairing file",
                status: .ok,
                detail: "RPPairing 形式の鍵を確認しました\(suffix)。サイズ \(data.count) bytes。"
            )
        }
        if hasLockdown {
            return ConnectionDiagnosticResult(
                title: "pairing file",
                status: .failure,
                detail: "lockdown 用の pairing file のみで、RPPairing の鍵（public_key / private_key / identifier）がありません。iloader でエクスポートした pairing file を使い直してください。"
            )
        }
        return ConnectionDiagnosticResult(
            title: "pairing file",
            status: .failure,
            detail: "RPPairing の鍵が見つかりません。iloader でエクスポートした pairing file を使い直してください。"
        )
    }

    private func wifiResult() async -> ConnectionDiagnosticResult {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "p2pgps.diagnostics.path")
            let lock = NSLock()
            var resumed = false

            func finish(_ result: ConnectionDiagnosticResult) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                continuation.resume(returning: result)
            }

            monitor.pathUpdateHandler = { path in
                let wifi = path.usesInterfaceType(.wifi)
                let satisfied = path.status == .satisfied
                if satisfied && wifi {
                    finish(
                        ConnectionDiagnosticResult(
                            title: "Wi-Fi",
                            status: .ok,
                            detail: "Wi-Fi に接続されています（RSD が開く条件を満たしています）。"
                        )
                    )
                } else if satisfied {
                    finish(
                        ConnectionDiagnosticResult(
                            title: "Wi-Fi",
                            status: .failure,
                            detail: "Wi-Fi 以外の経路（セルラー等）のみです。RSD は Wi-Fi 接続中しか開きません。Wi-Fi に接続してください。"
                        )
                    )
                } else {
                    finish(
                        ConnectionDiagnosticResult(
                            title: "Wi-Fi",
                            status: .failure,
                            detail: "ネットワークに接続されていません。Wi-Fi に接続してください。"
                        )
                    )
                }
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                finish(
                    ConnectionDiagnosticResult(
                        title: "Wi-Fi",
                        status: .warning,
                        detail: "Wi-Fi の状態を取得できませんでした。Wi-Fi に接続しているか確認してください。"
                    )
                )
            }
        }
    }

    private func tcpResult(port targetPort: UInt16) async -> ConnectionDiagnosticResult {
        let host = targetHost
        let portValue = targetPort
        return await withCheckedContinuation { continuation in
            guard let port = NWEndpoint.Port(rawValue: portValue) else {
                continuation.resume(
                    returning: ConnectionDiagnosticResult(
                        title: "\(host):\(portValue)",
                        status: .failure,
                        detail: "ポート番号が不正です。"
                    )
                )
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: port,
                using: .tcp
            )
            let queue = DispatchQueue(label: "p2pgps.diagnostics.tcp")
            let lock = NSLock()
            var resumed = false

            func finish(_ result: ConnectionDiagnosticResult) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(
                        ConnectionDiagnosticResult(
                            title: "\(host):\(portValue)",
                            status: .ok,
                            detail: "TCP 接続に成功しました。RSD に到達できています。"
                        )
                    )
                case .failed(let error):
                    finish(
                        ConnectionDiagnosticResult(
                            title: "\(host):\(portValue)",
                            status: .failure,
                            detail: "TCP 接続に失敗しました（\(error.localizedDescription)）。LocalDevVPN が接続済みか、他の VPN が有効でないか確認してください。"
                        )
                    )
                case .waiting(let error):
                    finish(
                        ConnectionDiagnosticResult(
                            title: "\(host):\(portValue)",
                            status: .failure,
                            detail: "接続待ちのまま応答がありません（\(error.localizedDescription)）。LocalDevVPN の接続・Wi-Fi・Developer Mode を確認してください。"
                        )
                    )
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) {
                finish(
                    ConnectionDiagnosticResult(
                        title: "\(host):\(portValue)",
                        status: .failure,
                        detail: "3 秒以内に接続できませんでした。LocalDevVPN が接続済みか、ターゲット IP が正しいか確認してください。"
                    )
                )
            }
        }
    }

    private func makeSummary(_ results: [ConnectionDiagnosticResult]) -> String {
        if results.contains(where: { $0.status == .failure }) {
            return "失敗した項目を上から順に確認してください。pairing file の形式が違う場合は、iloader でエクスポートし直してからインポートしてください。"
        }
        return "アプリ側の前提は満たしています。接続できない場合は VPN（LocalDevVPN）と Developer Mode を確認してください。"
    }
}
#endif
