//
//  ReceiverCentral.swift
//  P2PGPSBLE
//
//  P2P GPS — BLE central that receives Location Packets (spec §7).
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  This is the iPad side of the link: scan for the P2P GPS service, connect to
//  one sender, subscribe to Location / Status / Extended, write START, and hand
//  decoded fixes to the app. All CoreBluetooth callbacks arrive on the main
//  queue (the manager is created with `queue: .main`), so the `@Published`
//  properties are main-thread-only by construction.
//

import Combine
import CoreBluetooth
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSProtocol
#endif

/// A sender seen in an advertisement.
public struct DiscoveredSender: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let signalQuality: SignalQuality

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.signalQuality = SignalQuality(rssi: rssi)
    }
}

/// Connection state of the receiver.
public enum ReceiverConnectionState: Equatable {
    case idle
    case scanning
    case connecting(name: String)
    case connected(name: String)
    case disconnecting

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .disconnecting: return true
        case .idle, .connected: return false
        }
    }

    public var senderName: String? {
        switch self {
        case .connecting(let name), .connected(let name): return name
        case .idle, .scanning, .disconnecting: return nil
        }
    }
}

/// BLE central for the Receiver role.
public final class ReceiverCentral: NSObject, ObservableObject {
    // MARK: - Published state

    @Published public private(set) var state: ReceiverConnectionState = .idle
    @Published public private(set) var discoveredSenders: [DiscoveredSender] = []
    @Published public private(set) var latestFix: GPSFix?
    @Published public private(set) var latestPacket: LocationPacket?
    @Published public private(set) var latestExtended: ExtendedLocationPacket?
    @Published public private(set) var senderStatus: SenderStatus?
    @Published public private(set) var lastPacketHex: String = ""
    @Published public private(set) var packetsReceived: Int = 0
    @Published public private(set) var sequenceRewinds: Int = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastReceivedAt: Date?
    @Published public private(set) var signalQuality: SignalQuality = .none
    @Published public private(set) var isBluetoothAvailable: Bool = false
    @Published public private(set) var isScanning: Bool = false

    /// Notification (CCCD) subscription state, exposed for diagnostics.
    public var isLocationNotifying: Bool { locationCharacteristic?.isNotifying ?? false }
    public var isStatusNotifying: Bool { statusCharacteristic?.isNotifying ?? false }
    public var isExtendedNotifying: Bool { extendedCharacteristic?.isNotifying ?? false }

    // MARK: - Configuration

    /// Reconnect to the last sender after an unexpected disconnect.
    public var autoReconnect: Bool = true {
        didSet { defaults.set(autoReconnect, forKey: SettingsKey.autoReconnect) }
    }

    /// Called on the main queue for every accepted fix.
    public var onFix: ((GPSFix) -> Void)?
    /// Called on the main queue when the connection state changes.
    public var onStateChange: ((ReceiverConnectionState) -> Void)?
    /// Called on the main queue with a human-readable problem.
    public var onError: ((String) -> Void)?

    // MARK: - Private state

    private lazy var central: CBCentralManager = {
        CBCentralManager(delegate: self, queue: .main)
    }()

    private var wantedScan = false
    private var targetPeripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var locationCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var extendedCharacteristic: CBCharacteristic?
    private var filter = FixFilter()
    private var sequenceTracker = SequenceTracker()
    private var reconnectWorkItem: DispatchWorkItem?
    private var lastSenderName: String?
    private var lastSenderIdentifier: UUID?
    /// A user-requested disconnect must never trigger auto-reconnect (review M9).
    private var userInitiatedDisconnect = false
    /// Set while waiting for the allowed sender to reappear; `didDiscover`
    /// connects as soon as it does (review M10).
    private var isReconnectPending = false
    private var rssiTimer: Timer?
    private let defaults: UserDefaults
    private let log = LogStore.shared

    deinit {
        rssiTimer?.invalidate()
    }

    // MARK: - Init

    public override init() {
        self.defaults = UserDefaults.standard
        super.init()

        let defaults = self.defaults
        autoReconnect = defaults.object(forKey: SettingsKey.autoReconnect) as? Bool ?? true
        if let stored = defaults.string(forKey: SettingsKey.lastSenderIdentifier) {
            lastSenderIdentifier = UUID(uuidString: stored)
        }
        lastSenderName = defaults.string(forKey: SettingsKey.lastSenderName)

        _ = central // starts the manager and its delegate callbacks
    }

    // MARK: - Public API

    /// Starts scanning for P2P GPS senders.
    public func startScanning() {
        wantedScan = true
        guard central.state == .poweredOn else {
            log.warning("BLE スキャン開始を保留: central state = \(central.state.rawValue)")
            return
        }
        guard !isScanning else { return }
        discoveredSenders.removeAll()
        isScanning = true
        lastError = nil
        updateState(.scanning)
        central.scanForPeripherals(
            withServices: [BLEUUID.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log.info("P2P GPS 送信元のスキャンを開始しました")
    }

    /// Stops scanning. An established connection is kept.
    public func stopScanning() {
        wantedScan = false
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        if !state.isConnected {
            updateState(.idle)
        }
        log.info("スキャンを停止しました")
    }

    /// Connects to a discovered sender.
    public func connect(to sender: DiscoveredSender) {
        guard let peripheral = discoveredPeripheral(for: sender.id) else {
            reportError("送信元 \(sender.name) が見つかりません。もう一度スキャンしてください。")
            return
        }
        connect(peripheral: peripheral, name: sender.name)
    }

    /// Connects to the last sender the user used, if it is currently visible.
    public func connectToLastSenderIfVisible() {
        guard let identifier = lastSenderIdentifier,
              let peripheral = discoveredPeripheral(for: identifier) else { return }
        connect(peripheral: peripheral, name: lastSenderName ?? peripheral.name ?? "P2P GPS")
    }

    /// Disconnects and stops scanning.
    ///
    /// - Parameter userInitiated: `true` (default) suppresses auto-reconnect;
    ///   pass `false` only for internal teardown that should reconnect later.
    public func disconnect(userInitiated: Bool = true) {
        userInitiatedDisconnect = userInitiated
        isReconnectPending = false
        stopScanning()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopRSSIPolling()
        if let peripheral = targetPeripheral {
            updateState(.disconnecting)
            central.cancelPeripheralConnection(peripheral)
        } else {
            // Nothing to cancel, so no delegate callback will clear the flag.
            userInitiatedDisconnect = false
            updateState(.idle)
        }
    }

    /// Sends a Control command (spec §5). No-op when not connected.
    public func send(_ command: ControlCommand) {
        guard let peripheral = targetPeripheral,
              let characteristic = controlCharacteristic else {
            log.warning("Control コマンド \(command) を送信できません: 未接続")
            return
        }
        let data = command.encoded()
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        log.debug("Control 送信: \(command) (\(data.count) bytes)")
    }

    /// Convenience: START with the given interval.
    public func startStreaming(intervalMilliseconds: UInt16) {
        send(.start(intervalMilliseconds: intervalMilliseconds))
    }

    /// Convenience: STOP.
    public func stopStreaming() {
        send(.stop)
    }

    /// Convenience: one immediate fix.
    public func requestFix() {
        send(.requestFix)
    }

    /// Convenience: enable / disable Extended Location notifications.
    public func setExtendedEnabled(_ enabled: Bool) {
        send(.setExtended(enabled: enabled))
    }

    // MARK: - Private helpers

    private func discoveredPeripheral(for id: UUID) -> CBPeripheral? {
        if let known = discoveredPeripherals[id] {
            return known
        }
        return central.retrievePeripherals(withIdentifiers: [id]).first
    }

    private func connect(peripheral: CBPeripheral, name: String) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        userInitiatedDisconnect = false
        isReconnectPending = false
        // Never leave a second connection dangling (review L-22).
        if let existing = targetPeripheral, existing.identifier != peripheral.identifier {
            central.cancelPeripheralConnection(existing)
        }
        targetPeripheral = peripheral
        peripheral.delegate = self
        lastSenderName = name
        lastSenderIdentifier = peripheral.identifier
        defaults.set(name, forKey: SettingsKey.lastSenderName)
        defaults.set(peripheral.identifier.uuidString, forKey: SettingsKey.lastSenderIdentifier)
        updateState(.connecting(name: name))
        central.connect(peripheral, options: nil)
        log.info("送信元 \(name) に接続しています")
    }

    private func updateState(_ newState: ReceiverConnectionState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }

    private var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    private func reportError(_ message: String) {
        lastError = message
        log.error(message)
        onError?(message)
    }

    private func scheduleReconnectIfNeeded() {
        guard autoReconnect, !userInitiatedDisconnect, let identifier = lastSenderIdentifier else { return }
        isReconnectPending = true
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.autoReconnect, self.isReconnectPending else { return }
            guard let peripheral = self.discoveredPeripheral(for: identifier) else {
                // Not visible yet; keep `isReconnectPending` set so `didDiscover`
                // connects as soon as the allowed sender reappears (M10).
                self.startScanning()
                return
            }
            self.connect(peripheral: peripheral, name: self.lastSenderName ?? peripheral.name ?? "P2P GPS")
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        log.info("1 秒後に再スキャン / 再接続します")
    }

    private func startRSSIPolling() {
        stopRSSIPolling()
        targetPeripheral?.readRSSI()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.targetPeripheral?.readRSSI()
        }
    }

    private func stopRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    private func resetPeripheralState() {
        locationCharacteristic = nil
        controlCharacteristic = nil
        statusCharacteristic = nil
        extendedCharacteristic = nil
        filter.reset()
        sequenceTracker.reset()
        signalQuality = .none
        stopRSSIPolling()

        // Do not leave stale coordinates / "last received" data on screen (or
        // available to the injection controller) after a disconnect.
        latestFix = nil
        latestPacket = nil
        latestExtended = nil
        senderStatus = nil
        lastPacketHex = ""
        lastReceivedAt = nil
    }

    private func handleLocationValue(_ data: Data) {
        do {
            let packet = try LocationPacket.decode(data)
            latestPacket = packet
            lastPacketHex = packet.hexDescription
            packetsReceived += 1
            lastReceivedAt = Date()

            switch sequenceTracker.observe(packet.sequence) {
            case .rewound(let amount):
                sequenceRewinds += 1
                log.warning("sequence が \(amount) 巻き戻りました（パケットは受理、spec §3.3）")
            case .jumpedForward(let amount):
                log.debug("sequence が \(amount) 飛びました（パケット欠落）")
            case .duplicate:
                log.debug("重複した sequence を受信しました")
            case .first, .inOrder:
                break
            }

            guard packet.isUsableFix else {
                log.debug("有効な fix ではないため破棄: flags=\(packet.flags.rawValue) nullIsland=\(packet.isNullIsland)")
                return
            }

            let fix = packet.gpsFix(receivedAt: Date(), extended: latestExtended)
            switch filter.process(fix) {
            case .accepted(let filtered):
                latestFix = filtered
                onFix?(filtered)
            case .rejected(let reason):
                log.debug("fix を破棄: \(reason)")
            }
        } catch {
            log.error("Location Packet を破棄: \(error)")
        }
    }

    private func handleExtendedValue(_ data: Data) {
        do {
            latestExtended = try ExtendedLocationPacket.decode(data)
        } catch {
            log.error("Extended Location Packet を破棄: \(error)")
        }
    }

    private func handleStatusValue(_ data: Data) {
        do {
            senderStatus = try SenderStatus.decode(data)
        } catch {
            log.error("Status を破棄: \(error)")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ReceiverCentral: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let available = central.state == .poweredOn
        isBluetoothAvailable = available
        switch central.state {
        case .poweredOn:
            lastError = nil
            log.info("Bluetooth が利用可能になりました")
            if wantedScan {
                startScanning()
            } else if let identifier = lastSenderIdentifier,
                      let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first,
                      autoReconnect {
                connect(peripheral: peripheral, name: lastSenderName ?? peripheral.name ?? "P2P GPS")
            }
        case .poweredOff:
            // CoreBluetooth does not deliver didDisconnectPeripheral when the
            // radio is turned off, so tear down the link state explicitly.
            log.warning("Bluetooth がオフになりました。接続状態をリセットします")
            resetPeripheralState()
            targetPeripheral = nil
            isScanning = false
            updateState(.idle)
            reportError("Bluetooth がオフです。設定から Bluetooth をオンにしてください。")
        case .unauthorized:
            reportError("Bluetooth の使用が許可されていません。設定 > プライバシーとセキュリティ > Bluetooth で許可してください。")
        case .unsupported:
            reportError("このデバイスは BLE に対応していません。")
        case .resetting:
            log.warning("Bluetooth がリセットされました。接続状態をリセットします")
            resetPeripheralState()
            targetPeripheral = nil
            isScanning = false
            updateState(.idle)
        case .unknown:
            log.warning("Bluetooth の状態が不安定です (state=\(central.state.rawValue))")
        @unknown default:
            log.warning("未知の Bluetooth 状態です (state=\(central.state.rawValue))")
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? ""
        guard P2PGPS.isP2PGPSLocalName(name) else { return }

        discoveredPeripherals[peripheral.identifier] = peripheral
        let rssi = RSSI.intValue
        let sender = DiscoveredSender(id: peripheral.identifier, name: name, rssi: rssi)
        if let index = discoveredSenders.firstIndex(where: { $0.id == sender.id }) {
            discoveredSenders[index] = sender
        } else {
            discoveredSenders.append(sender)
            log.info("送信元を発見: \(name) (RSSI \(rssi) dBm)")
        }

        // Auto-reconnect only to the sender the user allowed, and only while a
        // reconnect is actually pending (review M10). A manual scan must not
        // hijack the connection.
        if isReconnectPending,
           autoReconnect,
           peripheral.identifier == lastSenderIdentifier,
           !state.isConnected,
           !isConnecting {
            connect(peripheral: peripheral, name: name)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? lastSenderName ?? "P2P GPS"
        lastError = nil
        userInitiatedDisconnect = false
        isReconnectPending = false
        // A connected peripheral must not leave the receiver in "scanning" UI
        // state; scanning also competes with the connection for radio time.
        stopScanning()
        updateState(.connected(name: name))
        startRSSIPolling()
        log.info("送信元 \(name) に接続しました。サービスを探索します")
        peripheral.discoverServices([BLEUUID.service])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetPeripheralState()
        updateState(.idle)
        if userInitiatedDisconnect {
            userInitiatedDisconnect = false
            log.info("ユーザー操作による接続キャンセル")
            return
        }
        reportError("送信元に接続できませんでした。近くに iPad があるか確認し、再試行してください。")
        scheduleReconnectIfNeeded()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        log.info("送信元から切断しました")
        resetPeripheralState()
        targetPeripheral = nil
        updateState(.idle)
        if userInitiatedDisconnect {
            userInitiatedDisconnect = false
            isReconnectPending = false
            log.info("ユーザー操作による切断のため自動再接続しません")
            return
        }
        scheduleReconnectIfNeeded()
    }
}

// MARK: - CBPeripheralDelegate

extension ReceiverCentral: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            reportError("Bluetooth の接続先が見つかりませんでした。送信側のアプリを確認してください。")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == BLEUUID.service }) else {
            reportError("P2P GPS サービスが見つかりません。送信側のアプリを確認してください。")
            return
        }
        peripheral.discoverCharacteristics(
            [BLEUUID.location, BLEUUID.control, BLEUUID.status, BLEUUID.extended],
            for: service
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            reportError("Bluetooth の設定を読み取れませんでした。送信側のアプリを確認してください。")
            return
        }
        for characteristic in service.characteristics ?? [] {
            log.info("キャラクタリスティックを発見: \(characteristic.uuid) properties=\(characteristic.properties.rawValue)")
            if characteristic.uuid == BLEUUID.location {
                locationCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == BLEUUID.status {
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            } else if characteristic.uuid == BLEUUID.extended {
                extendedCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == BLEUUID.control {
                controlCharacteristic = characteristic
            }
        }

        // Spec §5: after connecting, read Status and write START (idempotent).
        if locationCharacteristic == nil {
            reportError("この iPad は必要な Bluetooth 機能に対応していません。")
        }
        if statusCharacteristic == nil {
            reportError("この iPad は必要な Bluetooth 機能に対応していません。")
        }
        if controlCharacteristic != nil {
            let stored = UserDefaults.standard.integer(forKey: SettingsKey.senderIntervalMilliseconds)
            let interval = stored > 0 ? UInt16(clamping: stored) : ControlCommand.defaultIntervalMilliseconds
            send(.start(intervalMilliseconds: interval))
        } else {
            reportError("この iPad は必要な Bluetooth 機能に対応していません。")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            log.warning("値の受信に失敗 (\(characteristic.uuid)): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == BLEUUID.location {
            handleLocationValue(data)
        } else if characteristic.uuid == BLEUUID.extended {
            handleExtendedValue(data)
        } else if characteristic.uuid == BLEUUID.status {
            handleStatusValue(data)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            log.warning("notify 購読に失敗 (\(characteristic.uuid)): \(error.localizedDescription)")
            reportError("位置情報の受信設定に失敗しました。もう一度接続してください。")
        } else {
            log.info("通知購読: \(characteristic.uuid) isNotifying=\(characteristic.isNotifying)")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            log.warning("Control の書き込みに失敗: \(error.localizedDescription)")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        signalQuality = SignalQuality(rssi: RSSI.intValue)
    }
}
