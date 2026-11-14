//
//  DiagnosticsView.swift
//  P2PGPSApp
//
//  P2P GPS — Diagnostics (native List, DESIGN.md "Settings / Diagnostics").
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Shows raw packet hex, BLE state, FFI session state and the in-memory log so a
//  bug report can be written from the device without a Mac.
//

#if canImport(UIKit)
import Foundation
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
import P2PGPSInjection
#endif

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let central: ReceiverCentral?
    let engine: LocationSimulationEngine?
    let senderPeripheral: SenderPeripheral?

    var body: some View {
        NavigationStack {
            List {
                if let central {
                    Section("BLE 受信") {
                        ReceiverDiagnosticsRows(central: central)
                    }
                }
                if let senderPeripheral {
                    Section("BLE 送信") {
                        SenderDiagnosticsRows(peripheral: senderPeripheral)
                    }
                }
                if let engine {
                    Section("位置注入") {
                        InjectionDiagnosticsRows(engine: engine)
                    }
                }
                Section("トンネル / DDI") {
                    TunnelDiagnosticsRows()
                }
                Section("ログ") {
                    LogDiagnosticsRows()
                }
            }
            .scrollContentBackground(.hidden)
            .background(P2PColor.paper.ignoresSafeArea())
            .navigationTitle("診断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .tint(P2PColor.pine)
    }
}

// MARK: - Rows

/// One label/value row with a monospaced value.
private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(P2PFont.label)
                .foregroundStyle(P2PColor.inkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(P2PFont.monoCaption)
                .foregroundStyle(P2PColor.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// A multi-line hex dump row.
private struct HexRow: View {
    let label: String
    let hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(P2PFont.caption)
                .foregroundStyle(P2PColor.inkSecondary)
            Text(hex.isEmpty ? "—" : hex)
                .font(P2PFont.monoCaption)
                .foregroundStyle(P2PColor.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReceiverDiagnosticsRows: View {
    @ObservedObject var central: ReceiverCentral

    var body: some View {
        Group {
            DiagnosticRow(label: "状態", value: stateText)
            DiagnosticRow(label: "送信元", value: central.state.senderName ?? "—")
            DiagnosticRow(label: "電波", value: central.signalQuality.localizedDescription)
            DiagnosticRow(label: "受信パケット数", value: "\(central.packetsReceived)")
            DiagnosticRow(label: "sequence 巻き戻り", value: "\(central.sequenceRewinds)")
            HexRow(label: "最終 Location Packet", hex: central.lastPacketHex)
            HexRow(label: "最終 Status", hex: central.senderStatus?.hexDescription ?? "")
            HexRow(label: "最終 Extended", hex: central.latestExtended?.hexDescription ?? "")
        }
    }

    private var stateText: String {
        switch central.state {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .connecting(let name): return "connecting(\(name))"
        case .connected(let name): return "connected(\(name))"
        case .disconnecting: return "disconnecting"
        }
    }
}

private struct SenderDiagnosticsRows: View {
    @ObservedObject var peripheral: SenderPeripheral

    var body: some View {
        Group {
            DiagnosticRow(label: "状態", value: peripheral.state.localizedDescription)
            DiagnosticRow(label: "ローカル名", value: peripheral.localName)
            DiagnosticRow(label: "アドバタイズ", value: peripheral.isAdvertising ? "中" : "停止")
            DiagnosticRow(label: "購読数", value: "\(peripheral.subscriberCount)")
            DiagnosticRow(label: "最終 Control", value: peripheral.lastControlCommand.map { "\($0)" } ?? "—")
            if let error = peripheral.lastError {
                Text(error)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }
        }
    }
}

private struct InjectionDiagnosticsRows: View {
    @ObservedObject var engine: LocationSimulationEngine

    var body: some View {
        Group {
            DiagnosticRow(label: "シミュレーション", value: engine.isSimulating ? "実行中" : "停止")
            DiagnosticRow(label: "FFI セッション", value: engine.sessionOpen ? "open" : "closed")
            DiagnosticRow(label: "処理中", value: engine.isWorking ? "yes" : "no")
            DiagnosticRow(label: "DDI", value: engine.isDeveloperDiskImageMounted ? "マウント済み" : "未マウント")
            DiagnosticRow(label: "適用座標", value: appliedCoordinateText)
            DiagnosticRow(
                label: "最終反映",
                value: engine.lastSetAt.map { P2PFormat.relativeAge($0) } ?? "—"
            )
            if let error = engine.lastError {
                Text(error)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }
            Button {
                engine.refreshMountState()
            } label: {
                Label("DDI の状態を再取得", systemImage: "arrow.clockwise")
            }
        }
    }

    private var appliedCoordinateText: String {
        guard let latitude = engine.appliedLatitude, let longitude = engine.appliedLongitude else {
            return "—"
        }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }
}

private struct TunnelDiagnosticsRows: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var mounting = MountingProgress.shared

    var body: some View {
        Group {
            DiagnosticRow(label: "トンネル", value: tunnel.isConnected ? "接続済み" : (tunnel.isStarting ? "接続中" : "未接続"))
            DiagnosticRow(label: "ターゲット", value: "\(DeviceConnectionContext.targetIPAddress):49152")
            DiagnosticRow(label: "DDI マウント", value: mounting.isDeveloperDiskImageMounted ? "済み" : "未")
            if let error = tunnel.lastError {
                Text(error)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }
            if let error = mounting.lastError {
                Text(error)
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.danger)
            }
        }
    }
}

private struct LogDiagnosticsRows: View {
    @ObservedObject private var log = LogStore.shared

    var body: some View {
        Group {
            HStack(spacing: 12) {
                ShareLink(item: log.exportText()) {
                    Label("ログを共有", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button(role: .destructive) {
                    log.clear()
                } label: {
                    Label("消去", systemImage: "trash")
                }
            }

            ForEach(Array(log.entries.suffix(80).reversed())) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: entry.level.symbolName)
                        .font(.caption)
                        .foregroundStyle(color(for: entry.level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(P2PFont.monoCaption)
                            .foregroundStyle(P2PColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.timestamp, style: .time)
                            .font(P2PFont.caption)
                            .foregroundStyle(P2PColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if log.entries.isEmpty {
                Text("ログはありません")
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.inkSecondary)
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return P2PColor.inkSecondary
        case .info: return P2PColor.pine
        case .warning: return P2PColor.amber
        case .error: return P2PColor.danger
        }
    }
}
#endif
