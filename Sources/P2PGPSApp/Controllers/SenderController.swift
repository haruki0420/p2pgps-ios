//
//  SenderController.swift
//  P2PGPSApp
//
//  P2P GPS — Sender screen state: CoreLocation → BLE peripheral, Control machine.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §5 / §6 state machine: START / STOP / SET_INTERVAL / REQUEST_FIX /
//  SET_EXTENDED / RESET arrive as Control writes; the sender answers with
//  Status notifications. The local primary button starts advertising *and*
//  streaming; a receiver-initiated STOP only stops streaming (advertising
//  continues, spec §5), and losing the last subscriber returns the sender to
//  Idle (spec §7).
//
//  Review M11: settings changes (interval / Extended) are applied live through
//  Combine. Review L-1: RESET keeps streaming. Review L-25: battery is polled at
//  most every 5 seconds.
//

#if canImport(UIKit)
import Combine
import CoreLocation
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
import P2PGPSLocation
import P2PGPSProtocol
#endif

/// Coordinates the sender's location source, BLE peripheral and status machine.
final class SenderController: ObservableObject {
    // MARK: - Published state

    @Published private(set) var isStreaming = false
    @Published private(set) var isAdvertising = false
    @Published private(set) var intervalMilliseconds: UInt16
    @Published private(set) var extendedEnabled: Bool
    @Published private(set) var latestFix: GPSFix?
    @Published private(set) var status: SenderStatus = .idle
    @Published private(set) var subscriberCount = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var bleState: SenderPeripheral.State = .idle
    @Published private(set) var lastSentAt: Date?
    @Published var errorMessage: String?

    /// Stable advertised name (`P2PGPS-IOS-XXXX`).
    let localName: String = P2PGPS.randomLocalName(platform: .ios)

    // MARK: - Collaborators

    let location: SenderLocationService
    let peripheral: SenderPeripheral
    let settings: SettingsStore

    // MARK: - Private state

    private var sequence: UInt16 = 0
    private var lastSentAtInternal = Date.distantPast
    private var lastFixAvailability = false
    private var heartbeatTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var batteryPercentage: UInt8?
    private var batteryIsCharging = false
    private var batteryUpdatedAt = Date.distantPast
    private let log = LogStore.shared

    // MARK: - Init

    init(
        location: SenderLocationService = SenderLocationService(),
        peripheral: SenderPeripheral = SenderPeripheral(),
        settings: SettingsStore = .shared
    ) {
        self.location = location
        self.peripheral = peripheral
        self.settings = settings
        self.intervalMilliseconds = settings.senderIntervalMilliseconds
        self.extendedEnabled = settings.extendedLocationEnabled

        peripheral.localName = localName

        location.onFix = { [weak self] fix in
            self?.handleLocationFix(fix)
        }
        peripheral.onControlCommand = { [weak self] command in
            self?.handle(command)
        }
        peripheral.onControlError = { [weak self] error in
            self?.handle(error)
        }
        peripheral.onSubscribersChanged = { [weak self] count in
            self?.handleSubscribers(count)
        }

        location.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
            }
            .store(in: &cancellables)

        location.$lastError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)

        peripheral.$isAdvertising
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isAdvertising = value
            }
            .store(in: &cancellables)

        peripheral.$subscriberCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.subscriberCount = count
            }
            .store(in: &cancellables)

        peripheral.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.bleState = state
            }
            .store(in: &cancellables)

        // Settings changed from the Settings screen apply live (review M11).
        settings.$senderIntervalMilliseconds
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                guard let self, interval != self.intervalMilliseconds else { return }
                self.intervalMilliseconds = interval
                self.publishStatus(state: self.isStreaming ? .streaming : .idle)
            }
            .store(in: &cancellables)

        settings.$extendedLocationEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, enabled != self.extendedEnabled else { return }
                self.extendedEnabled = enabled
                self.publishStatus(state: self.isStreaming ? .streaming : .idle)
                if enabled, let fix = self.latestFix {
                    self.peripheral.update(extendedPacket: ExtendedLocationPacket(fix: fix))
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        heartbeatTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func onAppear() {
        location.refreshAuthorization()
        // Prime the readout before the user starts; this is not a keep-alive.
        location.requestOneShot()
    }

    /// Starts advertising and streaming.
    func startSending() {
        errorMessage = nil
        status.lastError = .none
        location.start()
        peripheral.startAdvertising(localName: localName)
        isStreaming = true
        publishStatus(state: .streaming)
        startHeartbeat()
        if let fix = latestFix {
            send(fix)
        }
        log.info("送信を開始しました (\(localName))")
    }

    /// Stops streaming and advertising (the local stop button).
    func stopSending() {
        status.lastError = .none
        isStreaming = false
        location.stop()
        peripheral.stopAdvertising()
        publishStatus(state: .idle)
        stopHeartbeat()
        log.info("送信を停止しました")
    }

    func toggleSending() {
        if isStreaming || isAdvertising {
            stopSending()
        } else {
            startSending()
        }
    }

    /// Re-reads the location authorization (after returning from Settings).
    func refreshAuthorization() {
        location.refreshAuthorization()
    }

    // MARK: - Location

    private func handleLocationFix(_ fix: GPSFix) {
        latestFix = fix
        if isStreaming {
            maybeSend(fix)
        }
        let hasFix = fix.isUsable
        if hasFix != lastFixAvailability {
            lastFixAvailability = hasFix
            publishStatus(state: isStreaming ? .streaming : .idle)
        }
    }

    private func maybeSend(_ fix: GPSFix) {
        let interval = Double(intervalMilliseconds) / 1000.0
        guard Date().timeIntervalSince(lastSentAtInternal) >= interval else { return }
        send(fix)
    }

    private func send(_ fix: GPSFix) {
        guard fix.isUsable else {
            status.lastError = .locationUnavailable
            peripheral.update(status: status)
            return
        }

        refreshBatteryIfNeeded()

        sequence &+= 1
        var extraFlags: LocationFlags = []
        if batteryIsCharging { extraFlags.insert(.charging) }
        if let battery = batteryPercentage, battery < 20 { extraFlags.insert(.lowBattery) }
        if let speed = fix.speedMetersPerSecond, speed >= 0.5 { extraFlags.insert(.moving) }

        let packet = LocationPacket(fix: fix, sequence: sequence, extraFlags: extraFlags)
        peripheral.update(locationPacket: packet)
        if extendedEnabled {
            peripheral.update(extendedPacket: ExtendedLocationPacket(fix: fix))
        }
        lastSentAtInternal = Date()
        lastSentAt = lastSentAtInternal
    }

    /// Battery monitoring is expensive enough to be worth throttling
    /// (review L-25).
    private func refreshBatteryIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(batteryUpdatedAt) >= 5 else { return }
        batteryUpdatedAt = now
        batteryPercentage = DeviceBattery.percentage
        batteryIsCharging = DeviceBattery.isCharging
    }

    // MARK: - Control characteristic

    private func handle(_ command: ControlCommand) {
        log.info("Control コマンドを適用: \(command)")
        // A successfully decoded command clears the previous error (review L-2).
        status.lastError = .none

        switch command {
        case .start:
            intervalMilliseconds = command.resolvedIntervalMilliseconds ?? intervalMilliseconds
            settings.senderIntervalMilliseconds = intervalMilliseconds
            if !isStreaming {
                location.start()
                isStreaming = true
            }
            publishStatus(state: .streaming)
            startHeartbeat()
            if let fix = latestFix {
                send(fix)
            }

        case .stop:
            isStreaming = false
            location.stop()
            publishStatus(state: .idle)
            stopHeartbeat()

        case .setInterval:
            intervalMilliseconds = command.resolvedIntervalMilliseconds ?? intervalMilliseconds
            settings.senderIntervalMilliseconds = intervalMilliseconds
            publishStatus(state: isStreaming ? .streaming : .idle)

        case .requestFix:
            if let fix = latestFix {
                send(fix)
            } else {
                location.requestOneShot()
                status.lastError = .locationUnavailable
                publishStatus(state: isStreaming ? .streaming : .idle)
            }

        case .setExtended(let enabled):
            extendedEnabled = enabled
            settings.extendedLocationEnabled = enabled
            publishStatus(state: isStreaming ? .streaming : .idle)
            if enabled, let fix = latestFix {
                peripheral.update(extendedPacket: ExtendedLocationPacket(fix: fix))
            }

        case .reset:
            // Spec §5: RESET restores defaults (interval 1000, extended off,
            // sequence 0) but does not stop streaming (review L-1).
            intervalMilliseconds = ControlCommand.defaultIntervalMilliseconds
            settings.senderIntervalMilliseconds = intervalMilliseconds
            extendedEnabled = false
            settings.extendedLocationEnabled = false
            sequence = 0
            publishStatus(state: isStreaming ? .streaming : .idle)
        }
    }

    private func handle(_ error: ControlCommandError) {
        switch error {
        case .unknownOpcode:
            status.lastError = .unknownOpcode
        case .badLength, .empty:
            status.lastError = .badLength
        }
        log.warning("Control コマンドを無視しました: \(error)")
        peripheral.update(status: status)
    }

    private func handleSubscribers(_ count: Int) {
        subscriberCount = count
        // Spec §7: with no subscribers the sender returns to Idle and keeps
        // advertising.
        if count == 0 && isStreaming {
            isStreaming = false
            location.stop()
            publishStatus(state: .idle)
            stopHeartbeat()
            log.info("購読者がいなくなったため Idle に戻りました（アドバタイズは継続）")
        }
    }

    // MARK: - Status

    private func makeStatus(state: SenderStatus.State) -> SenderStatus {
        var flags: SenderStatus.Flags = []
        if extendedEnabled { flags.insert(.extendedEnabled) }
        if latestFix?.isUsable == true { flags.insert(.fixAvailable) }
        if batteryIsCharging { flags.insert(.charging) }
        if let battery = batteryPercentage, battery < 20 { flags.insert(.lowBattery) }
        return SenderStatus(
            state: state,
            intervalMilliseconds: intervalMilliseconds,
            batteryPercentage: batteryPercentage ?? SenderStatus.unknownBattery,
            flags: flags,
            lastError: status.lastError
        )
    }

    private func publishStatus(state: SenderStatus.State) {
        status = makeStatus(state: state)
        peripheral.update(status: status)
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.publishStatus(state: self.isStreaming ? .streaming : .idle)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Derived UI state

    var fixQualityLevel: Int {
        FixQualityBars.level(forAccuracy: latestFix?.horizontalAccuracyMeters)
    }

    var coordinateText: String {
        guard let fix = latestFix else { return "—" }
        return fix.coordinateDescription(decimalPlaces: 7)
    }

    var stateText: String {
        if isStreaming {
            return "送信中（\(P2PFormat.interval(intervalMilliseconds)) 間隔）"
        }
        if isAdvertising {
            return "停止中（アドバタイズ中）"
        }
        return "停止中"
    }

    /// Whether the BLE layer reported a problem (review L-20).
    var hasPeripheralError: Bool {
        peripheral.lastError != nil
    }
}
#endif
