//
//  ReceiverView.swift
//  P2PGPSApp
//
//  P2P GPS — Receiver screen (iPad): status rail, full-bleed map, readout plate.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  DESIGN.md "Receiver": status rail → map with crosshair + range rings and a
//  pine trail → readout plate with the two coordinate lines, secondary metrics
//  and the 52pt live toggle. While injecting, a live banner is pinned to the
//  top safe area.
//

#if canImport(UIKit)
import Foundation
import CoreLocation
import MapKit
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
import P2PGPSInjection
#endif

struct ReceiverView: View {
    @ObservedObject var controller: ReceiverController
    @ObservedObject private var central: ReceiverCentral
    @ObservedObject private var engine: LocationSimulationEngine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnFix = false
    @State private var isShowingSettings = false
    @State private var isShowingDiagnostics = false

    init(controller: ReceiverController) {
        self.controller = controller
        self._central = ObservedObject(wrappedValue: controller.central)
        self._engine = ObservedObject(wrappedValue: controller.engine)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusRail(
                ledState: ledState,
                senderName: controller.senderName,
                lastReceivedAt: central.lastReceivedAt,
                signalQuality: central.signalQuality,
                accuracyText: controller.accuracyText,
                statusText: statusText
            )

            mapSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ReadoutPlate {
                readoutContent
            }
        }
        .background(P2PColor.paper.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            if controller.isInjecting {
                LiveBanner(
                    senderName: controller.senderName,
                    coordinateText: controller.injectedCoordinateText
                ) {
                    controller.setInjection(false)
                }
            }
        }
        .navigationTitle("受信")
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
                central: central,
                engine: engine,
                senderPeripheral: nil
            )
        }
        .onAppear {
            controller.onAppear()
            centerIfNeeded()
        }
        .onChange(of: central.latestFix?.latitude) { _, _ in
            centerIfNeeded()
        }
        .onChange(of: central.latestFix == nil) { _, isNil in
            // Re-center on the next sender after a disconnect.
            if isNil {
                hasCenteredOnFix = false
            }
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            if let fix = central.latestFix {
                Annotation(
                    "受信位置",
                    coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
                ) {
                    MapCrosshairMarker()
                }
            }
            if controller.trail.count > 1 {
                MapPolyline(coordinates: controller.trail)
                    .stroke(
                        P2PColor.pine.opacity(0.7),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                hasCenteredOnFix = false
                centerIfNeeded(force: true)
            } label: {
                Image(systemName: "location")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(P2PColor.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                            .fill(P2PColor.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                            .stroke(P2PColor.line, lineWidth: 1)
                    )
            }
            .padding(12)
            .accessibilityLabel("受信位置を中心に表示")
            .opacity(central.latestFix == nil ? 0 : 1)
        }
    }

    private func centerIfNeeded(force: Bool = false) {
        guard (force || !hasCenteredOnFix), let fix = central.latestFix else { return }
        hasCenteredOnFix = true
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        if reduceMotion {
            cameraPosition = .region(region)
        } else {
            withAnimation(.easeInOut(duration: 0.4)) {
                cameraPosition = .region(region)
            }
        }
    }

    // MARK: - Readout

    @ViewBuilder
    private var readoutContent: some View {
        if let fix = central.latestFix {
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
                MetricItem(label: "標高", value: P2PFormat.altitude(fix.altitudeMeters))
                MetricItem(label: "精度", value: P2PFormat.accuracy(fix.horizontalAccuracyMeters))
                MetricItem(label: "速度", value: P2PFormat.speed(fix.speedMetersPerSecond))
                MetricItem(label: "更新", value: P2PFormat.relativeAge(central.lastReceivedAt))
            }

            if fix.isStale(now: Date()) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(P2PColor.amber)
                    Text("位置情報が古すぎます（24 時間以上前）。送信側の時刻設定を確認し、もう一度送信してください。")
                        .font(P2PFont.caption)
                        .foregroundStyle(P2PColor.inkSecondary)
                }
            }

            LiveToggleButton(
                isOn: controller.wantsInjection,
                offTitle: "位置情報を反映",
                onTitle: "反映を停止"
            ) {
                controller.toggleInjection()
            }

            if let error = controller.errorMessage {
                P2PErrorRow(message: error)
            }
        } else {
            waitingContent
        }
    }

    @ViewBuilder
    private var waitingContent: some View {
        if central.state.isConnected {
            P2PEmptyState(
                systemImage: "checkmark.circle",
                title: "接続済み・位置データ待ち",
                message: "接続できました。送信側が現在地を測位できると、ここに位置が表示されます。"
            )

            if let error = controller.errorMessage {
                P2PErrorRow(message: error)
            }
        } else {
            P2PEmptyState(
                systemImage: "antenna.radiowaves.left.and.right",
                title: central.isScanning ? "送信元を探しています" : "まだ受信していません",
                message: "iPhone / Android 側で「送信を開始」を押すと、ここに送信元が表示されます。"
            )

            if !central.discoveredSenders.isEmpty {
                VStack(spacing: 0) {
                    ForEach(central.discoveredSenders) { sender in
                        Button {
                            controller.connect(to: sender)
                        } label: {
                            HStack(spacing: 10) {
                                SignalBars(quality: sender.signalQuality)
                                Text(sender.name)
                                    .font(P2PFont.monoCaption)
                                    .foregroundStyle(P2PColor.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("接続")
                                    .font(P2PFont.labelEmphasis)
                                    .foregroundStyle(P2PColor.pine)
                            }
                            .frame(minHeight: P2PSpacing.minimumTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sender.name) に接続")

                        Rectangle()
                            .fill(P2PColor.line)
                            .frame(height: P2PSpacing.hairline)
                    }
                }
            }

            PrimaryActionButton(
                title: central.isScanning ? "スキャン中…" : "スキャン開始",
                systemImage: "magnifyingglass",
                isEnabled: !central.isScanning && !central.state.isConnected
            ) {
                controller.startScanning()
            }

            if let error = controller.errorMessage {
                P2PErrorRow(message: error)
            }
        }
    }

    // MARK: - Derived state

    private var ledState: ConnectionLED.State {
        switch central.state {
        case .connected:
            return .connected
        case .connecting, .scanning:
            return .waiting
        case .idle, .disconnecting:
            return controller.errorMessage == nil ? .idle : .error
        }
    }

    private var statusText: String {
        switch central.state {
        case .connected:
            return "接続済み"
        case .connecting:
            return "接続中"
        case .scanning:
            return "スキャン中"
        case .disconnecting:
            return "切断中"
        case .idle:
            return "未接続"
        }
    }
}
#endif
