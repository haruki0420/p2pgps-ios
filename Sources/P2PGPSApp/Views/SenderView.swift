//
//  SenderView.swift
//  P2PGPSApp
//
//  P2P GPS — Sender screen (iPhone): readout plate, state, primary action.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  DESIGN.md "Sender": readout plate at the top, state text and interval in the
//  middle, 52pt primary action at the bottom, and the three BLE states spelled
//  out (advertising / subscribed / streaming).
//

#if canImport(UIKit)
import Foundation
import CoreLocation
import SwiftUI
import UIKit
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
import P2PGPSLocation
#endif

struct SenderView: View {
    @ObservedObject var controller: SenderController

    @State private var isShowingSettings = false
    @State private var isShowingDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            StatusRail(
                ledState: ledState,
                senderName: controller.localName,
                lastReceivedAt: controller.lastSentAt,
                signalQuality: signalQuality,
                accuracyText: "受信中の iPad \(controller.subscriberCount) 台",
                statusText: controller.bleState.localizedDescription,
                lastEventLabel: "最終送信"
            )

            ScrollView {
                VStack(spacing: 0) {
                    ReadoutPlate {
                        coordinateContent
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        stateSection
                        bleSection

                        if needsLocationPermission {
                            permissionSection
                        }

                        if let error = controller.errorMessage {
                            P2PErrorRow(message: error)
                        }

                        PrimaryActionButton(
                            title: actionTitle,
                            systemImage: isSending ? "stop.circle" : "antenna.radiowaves.left.and.right"
                        ) {
                            controller.toggleSending()
                        }

                        Text("送信を開始すると Bluetooth で見つけられる状態になり、受信側が接続すると位置を送ります。画面を消しても送信を続けるため、位置情報の「常に許可」を推奨します。")
                            .font(P2PFont.caption)
                            .foregroundStyle(P2PColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(P2PSpacing.gutter)
                }
            }
        }
        .background(P2PColor.paper.ignoresSafeArea())
        .navigationTitle("送信")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingDiagnostics = true
                } label: {
                    Image(systemName: "waveform.path.ecg")
                }
                .accessibilityLabel("困ったとき")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView(
                central: nil,
                engine: nil,
                senderPeripheral: controller.peripheral
            )
        }
        .onAppear {
            controller.onAppear()
        }
    }

    // MARK: - Readout plate

    @ViewBuilder
    private var coordinateContent: some View {
        if let fix = controller.latestFix {
            CoordinateRow(
                label: "緯度",
                value: P2PFormat.coordinate(fix.latitude),
                spokenValue: P2PFormat.spokenLatitude(fix.latitude)
            )
            CoordinateRow(
                label: "経度",
                value: P2PFormat.coordinate(fix.longitude),
                spokenValue: P2PFormat.spokenLongitude(fix.longitude)
            )
            HStack(alignment: .top, spacing: 12) {
                MetricItem(label: "精度", value: P2PFormat.accuracy(fix.horizontalAccuracyMeters))
                MetricItem(label: "標高", value: P2PFormat.altitude(fix.altitudeMeters))
                MetricItem(label: "速度", value: P2PFormat.speed(fix.speedMetersPerSecond))
                VStack(alignment: .leading, spacing: 4) {
                    Text("測位の精度")
                        .font(P2PFont.caption)
                        .foregroundStyle(P2PColor.inkSecondary)
                    FixQualityBars(level: controller.fixQualityLevel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            P2PEmptyState(
                systemImage: "location.slash",
                title: "まだ測位していません",
                message: "屋外または Wi-Fi 接続のある場所で、位置情報の許可を確認してください。"
            )
        }
    }

    // MARK: - State sections

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.stateText)
                .font(P2PFont.labelEmphasis)
                .foregroundStyle(controller.isStreaming ? P2PColor.pine : P2PColor.ink)
            Text("送信間隔 \(P2PFormat.interval(controller.intervalMilliseconds))")
                .font(P2PFont.metric)
                .foregroundStyle(P2PColor.inkSecondary)
            if controller.extendedEnabled {
                Text("速度と向きも送ります")
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var bleSection: some View {
        HStack(alignment: .top, spacing: 12) {
            bleItem(
                title: "見つけられる状態",
                value: controller.isAdvertising ? "公開中" : "停止",
                isActive: controller.isAdvertising,
                systemImage: "dot.radiowaves.left.and.right"
            )
            bleItem(
                title: "受信中の iPad",
                value: "\(controller.subscriberCount) 台",
                isActive: controller.subscriberCount > 0,
                systemImage: "link"
            )
            bleItem(
                title: "位置の送信",
                value: controller.isStreaming ? "中" : "停止",
                isActive: controller.isStreaming,
                systemImage: "arrow.up.circle"
            )
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(P2PColor.line).frame(height: P2PSpacing.hairline)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(P2PColor.line).frame(height: P2PSpacing.hairline)
        }
    }

    private func bleItem(title: String, value: String, isActive: Bool, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(P2PFont.caption)
            }
            .foregroundStyle(isActive ? P2PColor.pine : P2PColor.inkSecondary)
            Text(value)
                .font(P2PFont.metric)
                .foregroundStyle(P2PColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            P2PErrorRow(message: "位置情報が許可されていません。設定アプリの「プライバシーとセキュリティ > 位置情報サービス」でこのアプリを許可してください。")
            Button {
                openSettings()
            } label: {
                Label("設定アプリを開く", systemImage: "gear")
                    .font(P2PFont.labelEmphasis)
                    .foregroundStyle(P2PColor.pine)
                    .frame(minHeight: P2PSpacing.minimumTapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Derived state

    private var isSending: Bool {
        controller.isStreaming || controller.isAdvertising
    }

    private var actionTitle: String {
        if controller.isStreaming { return "送信を停止" }
        if controller.isAdvertising { return "接続待ちをやめる" }
        return "送信を開始"
    }

    private var needsLocationPermission: Bool {
        switch controller.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    private var ledState: ConnectionLED.State {
        // A BLE error is the most important state to surface (review L-20).
        if controller.hasPeripheralError {
            return .error
        }
        if controller.isStreaming && controller.subscriberCount > 0 {
            return .connected
        }
        if controller.isAdvertising {
            return .waiting
        }
        return .idle
    }

    private var signalQuality: SignalQuality {
        controller.subscriberCount > 0 ? .good : .none
    }
}
#endif
