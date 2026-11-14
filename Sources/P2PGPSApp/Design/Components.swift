//
//  Components.swift
//  P2PGPSApp
//
//  P2P GPS — shared UI components from DESIGN.md "Components".
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Every component here is a direct translation of a DESIGN.md row. They use
//  system controls and semantic tokens only: no shadows, no gradients, no
//  custom navigation, no emoji iconography.
//

#if canImport(UIKit)
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
#endif

// MARK: - Status rail

/// Connection LED: filled when connected, outlined when idle, pulsing while
/// connecting/scanning (DESIGN.md "Status rail" / "Motion").
struct ConnectionLED: View {
    enum State {
        case connected
        case waiting
        case error
        case idle

        var color: Color {
            switch self {
            case .connected: return P2PColor.pine
            case .waiting: return P2PColor.amber
            case .error: return P2PColor.danger
            case .idle: return P2PColor.inkSecondary
            }
        }

        var isFilled: Bool {
            switch self {
            case .connected, .waiting, .error: return true
            case .idle: return false
            }
        }
    }

    let state: State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(state.isFilled ? state.color : Color.clear)
            .overlay(Circle().stroke(state.color, lineWidth: state.isFilled ? 0 : 1.5))
            .frame(width: P2PSpacing.ledDiameter, height: P2PSpacing.ledDiameter)
            .opacity(pulse ? 0.35 : 1)
            .onAppear { updatePulse() }
            .onChange(of: state) { _, _ in updatePulse() }
            .accessibilityHidden(true)
    }

    private func updatePulse() {
        guard state == .waiting, !reduceMotion else {
            pulse = false
            return
        }
        withAnimation(.easeInOut(duration: P2PMotion.ledPulse).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

/// Four vertical bars showing link quality (DESIGN.md "Signal bars").
struct SignalBars: View {
    let quality: SignalQuality

    var body: some View {
        HStack(alignment: .center, spacing: P2PSpacing.signalBarSpacing) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(index < quality.rawValue ? P2PColor.ink : P2PColor.line)
                    .frame(width: P2PSpacing.signalBarWidth, height: P2PSpacing.signalBarHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("電波強度 \(quality.localizedDescription)")
    }
}

/// Top status rail: LED + sender, last received, signal + accuracy.
struct StatusRail: View {
    let ledState: ConnectionLED.State
    let senderName: String?
    let lastReceivedAt: Date?
    let signalQuality: SignalQuality
    let accuracyText: String
    let statusText: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ConnectionLED(state: ledState)
                VStack(alignment: .leading, spacing: 1) {
                    Text(senderName ?? "未接続")
                        .font(P2PFont.labelEmphasis)
                        .foregroundStyle(P2PColor.ink)
                        .lineLimit(1)
                    if let statusText {
                        Text(statusText)
                            .font(P2PFont.caption)
                            .foregroundStyle(P2PColor.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text("最終受信 \(P2PFormat.relativeAge(lastReceivedAt, now: context.date))")
                    .font(P2PFont.metric)
                    .foregroundStyle(P2PColor.inkSecondary)
                    .lineLimit(1)
                SignalBars(quality: signalQuality)
                Text(accuracyText)
                    .font(P2PFont.metric)
                    .foregroundStyle(P2PColor.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, P2PSpacing.gutter)
            .frame(height: P2PSpacing.railHeight)
            .background(P2PColor.paper)
            .p2pHairline()
        }
    }
}

// MARK: - Readout plate

/// The bottom readout plate: surface, 16pt top corners, hairline top edge.
struct ReadoutPlate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(P2PSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: P2PSpacing.plateCorner,
                topTrailingRadius: P2PSpacing.plateCorner
            )
            .fill(P2PColor.surface)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(P2PColor.line)
                .frame(height: P2PSpacing.hairline)
        }
    }
}

/// One labelled coordinate line. The value is the largest numeral on screen.
struct CoordinateRow: View {
    let label: String
    let value: String
    let spokenValue: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(P2PFont.label)
                .foregroundStyle(P2PColor.inkSecondary)
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(P2PFont.coordinate)
                .monospacedDigit()
                .foregroundStyle(P2PColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(spokenValue)")
    }
}

/// One secondary metric (altitude / accuracy / speed / update age).
struct MetricItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(P2PFont.caption)
                .foregroundStyle(P2PColor.inkSecondary)
                .lineLimit(1)
            Text(value)
                .font(P2PFont.metric)
                .monospacedDigit()
                .foregroundStyle(P2PColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

// MARK: - Buttons

/// Press feedback: a 0.98 scale, no animation (direct manipulation only).
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

/// 52pt primary action, pine fill, paper-colored text (DESIGN.md "Primary action").
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(P2PFont.labelEmphasis)
            }
            .foregroundStyle(P2PColor.paper)
            .frame(maxWidth: .infinity)
            .frame(height: P2PSpacing.primaryHeight)
            .background(
                RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                    .fill(P2PColor.pine)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}

/// 52pt live toggle: OFF is surface + hairline, ON is liveFill + a 3pt live bar.
struct LiveToggleButton: View {
    let isOn: Bool
    let offTitle: String
    let onTitle: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "stop.circle.fill" : "location.fill")
                    .font(.body.weight(.semibold))
                Text(isOn ? onTitle : offTitle)
                    .font(P2PFont.labelEmphasis)
                Spacer(minLength: 0)
                Text(isOn ? "ON" : "OFF")
                    .font(P2PFont.metric)
                    .opacity(0.8)
            }
            .foregroundStyle(isOn ? P2PColor.paper : P2PColor.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: P2PSpacing.primaryHeight)
            .background(
                RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                    .fill(isOn ? P2PColor.liveFill : P2PColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                    .stroke(isOn ? Color.clear : P2PColor.line, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if isOn {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(P2PColor.live)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .padding(.leading, 3)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(isOn ? onTitle : offTitle)
        .accessibilityValue(isOn ? "オン" : "オフ")
    }
}

/// Injected-state banner pinned to the top safe area (DESIGN.md "Live banner").
struct LiveBanner: View {
    let senderName: String?
    let coordinateText: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(P2PColor.live)
            VStack(alignment: .leading, spacing: 2) {
                Text("位置情報を反映中")
                    .font(P2PFont.labelEmphasis)
                    .foregroundStyle(P2PColor.ink)
                Text("\(senderName ?? "送信元不明")  \(coordinateText)")
                    .font(P2PFont.monoCaption)
                    .foregroundStyle(P2PColor.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("停止", action: onStop)
                .font(P2PFont.labelEmphasis)
                .foregroundStyle(P2PColor.live)
                .frame(minWidth: P2PSpacing.minimumTapTarget, minHeight: P2PSpacing.minimumTapTarget)
                .accessibilityLabel("位置情報の反映を停止")
        }
        .padding(.horizontal, P2PSpacing.gutter)
        .padding(.vertical, 6)
        .background(P2PColor.liveFill.opacity(0.1))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(P2PColor.live)
                .frame(width: 3)
        }
    }
}

// MARK: - Map marker

/// Crosshair + range rings drawn at the received coordinate (DESIGN.md
/// "Range rings"). The rings are screen-space guides, not surveyed distances.
struct MapCrosshairMarker: View {
    var body: some View {
        ZStack {
            ForEach([88.0, 156.0, 232.0], id: \.self) { diameter in
                Circle()
                    .stroke(P2PColor.pine.opacity(0.12), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
            }
            Circle()
                .stroke(P2PColor.pine, lineWidth: 1.5)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(P2PColor.pine)
                .frame(width: 1, height: 24)
            Rectangle()
                .fill(P2PColor.pine)
                .frame(width: 24, height: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Section header

/// A plain section label. Not an ALL CAPS eyebrow (DESIGN.md anti-slop rule).
struct P2PSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(P2PFont.labelEmphasis)
            .foregroundStyle(P2PColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

// MARK: - Role row

/// One large role row on Home (not a card).
struct RoleRow: View {
    let role: AppRole

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: role.symbolName)
                .font(.title3)
                .foregroundStyle(P2PColor.pine)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(role.title)
                    .font(P2PFont.rowTitle)
                    .foregroundStyle(P2PColor.ink)
                Text(role.subtitle)
                    .font(P2PFont.label)
                    .foregroundStyle(P2PColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(P2PColor.inkSecondary)
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.title)。\(role.subtitle)")
    }
}

// MARK: - Empty / error states

/// A quiet empty state: icon + one sentence + the next action.
struct P2PEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(P2PColor.inkSecondary)
            Text(title)
                .font(P2PFont.labelEmphasis)
                .foregroundStyle(P2PColor.ink)
            Text(message)
                .font(P2PFont.label)
                .foregroundStyle(P2PColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}

/// Inline error: icon + two-sentence recovery text (DESIGN.md "Copy").
struct P2PErrorRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(P2PColor.danger)
            Text(message)
                .font(P2PFont.label)
                .foregroundStyle(P2PColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                .fill(P2PColor.danger.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: P2PSpacing.controlCorner)
                .stroke(P2PColor.danger.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fix quality

/// Four-segment fix quality indicator for the Sender plate.
struct FixQualityBars: View {
    /// 0 = no fix, 4 = excellent.
    let level: Int

    var body: some View {
        HStack(spacing: P2PSpacing.signalBarSpacing) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(index < level ? P2PColor.pine : P2PColor.line)
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("fix 品質 \(level) / 4")
    }

    /// Maps a horizontal accuracy in metres to 0–4.
    static func level(forAccuracy accuracy: Double?) -> Int {
        guard let accuracy, accuracy >= 0 else { return 0 }
        switch accuracy {
        case ...10: return 4
        case ...30: return 3
        case ...100: return 2
        default: return 1
        }
    }
}
#endif
