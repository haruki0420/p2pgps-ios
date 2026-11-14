//
//  SenderPeripheral.swift
//  P2PGPSBLE
//
//  P2P GPS — BLE peripheral that transmits Location Packets (spec §7).
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  The iPhone side of the link. It owns the GATT server and the cached
//  characteristic values (a read must return the last sent value, spec §1.1);
//  the streaming state machine lives in `SenderController` in the app target,
//  which reacts to the Control commands forwarded here.
//

import Combine
import CoreBluetooth
import Foundation
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSProtocol
#endif

/// BLE peripheral for the Sender role.
public final class SenderPeripheral: NSObject, ObservableObject {
    /// Coarse state used by the UI's BLE indicator.
    public enum State: Equatable {
        case poweredOff
        case idle
        case advertising
        case subscribed(count: Int)

        public var localizedDescription: String {
            switch self {
            case .poweredOff: return "Bluetooth オフ"
            case .idle: return "待機中"
            case .advertising: return "アドバタイズ中"
            case .subscribed(let count): return "接続 \(count) 台"
            }
        }
    }

    // MARK: - Published state

    @Published public private(set) var state: State = .idle
    @Published public private(set) var isAdvertising = false
    @Published public private(set) var subscriberCount = 0
    @Published public private(set) var isBluetoothAvailable = false
    @Published public private(set) var lastControlCommand: ControlCommand?
    @Published public private(set) var lastError: String?

    // MARK: - Configuration

    /// Advertised local name (`P2PGPS-IOS-XXXX` unless overridden).
    public var localName: String = P2PGPS.randomLocalName(platform: .ios)

    /// Forwarded on the main queue for every valid Control write.
    public var onControlCommand: ((ControlCommand) -> Void)?
    /// Forwarded on the main queue when a Control write was malformed.
    public var onControlError: ((ControlCommandError) -> Void)?
    /// Forwarded on the main queue when the subscriber count changes.
    public var onSubscribersChanged: ((Int) -> Void)?

    // MARK: - Private state

    private lazy var manager: CBPeripheralManager = {
        CBPeripheralManager(delegate: self, queue: .main)
    }()

    private var service: CBMutableService?
    private var deviceInformationService: CBMutableService?
    private var locationCharacteristic: CBMutableCharacteristic?
    private var controlCharacteristic: CBMutableCharacteristic?
    private var statusCharacteristic: CBMutableCharacteristic?
    private var extendedCharacteristic: CBMutableCharacteristic?

    private var lastLocationData = LocationPacket.invalid.encoded()
    private var lastExtendedData = ExtendedLocationPacket.invalid.encoded()
    private var lastStatusData = SenderStatus.idle.encoded()

    private var pendingAdvertising = false
    private var subscribedCentralIDs: Set<UUID> = []
    private let log = LogStore.shared

    // MARK: - Init

    public override init() {
        super.init()
        _ = manager
    }

    // MARK: - Public API

    /// Starts advertising the P2P GPS service.
    public func startAdvertising(localName: String? = nil) {
        if let localName {
            self.localName = localName
        }
        pendingAdvertising = true
        guard manager.state == .poweredOn else {
            log.warning("アドバタイズ開始を保留: peripheral state = \(manager.state.rawValue)")
            return
        }
        if service == nil {
            addServices()
        } else if !manager.isAdvertising {
            beginAdvertising()
        }
    }

    /// Stops advertising. A connected central stays connected until it leaves.
    public func stopAdvertising() {
        pendingAdvertising = false
        if manager.isAdvertising {
            manager.stopAdvertising()
        }
        isAdvertising = false
        updateState()
        log.info("アドバタイズを停止しました")
    }

    /// Caches and notifies the latest Location Packet.
    public func update(locationPacket: LocationPacket) {
        lastLocationData = locationPacket.encoded()
        notifyIfSubscribed(lastLocationData, characteristic: locationCharacteristic)
    }

    /// Caches and notifies the latest Extended Location Packet.
    public func update(extendedPacket: ExtendedLocationPacket) {
        lastExtendedData = extendedPacket.encoded()
        notifyIfSubscribed(lastExtendedData, characteristic: extendedCharacteristic)
    }

    /// Caches and notifies the latest Status packet.
    public func update(status: SenderStatus) {
        lastStatusData = status.encoded()
        notifyIfSubscribed(lastStatusData, characteristic: statusCharacteristic)
    }

    /// Caches the Status without notifying (used for the read-before-notify path).
    public func cache(status: SenderStatus) {
        lastStatusData = status.encoded()
    }

    // MARK: - Private helpers

    private func addServices() {
        let location = CBMutableCharacteristic(
            type: BLEUUID.location,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let control = CBMutableCharacteristic(
            type: BLEUUID.control,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let status = CBMutableCharacteristic(
            type: BLEUUID.status,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let extended = CBMutableCharacteristic(
            type: BLEUUID.extended,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )

        let service = CBMutableService(type: BLEUUID.service, primary: true)
        service.characteristics = [location, control, status, extended]
        self.locationCharacteristic = location
        self.controlCharacteristic = control
        self.statusCharacteristic = status
        self.extendedCharacteristic = extended
        self.service = service

        let manufacturer = CBMutableCharacteristic(
            type: BLEUUID.manufacturerName,
            properties: [.read],
            value: Data(P2PGPS.manufacturerName.utf8),
            permissions: [.readable]
        )
        let model = CBMutableCharacteristic(
            type: BLEUUID.modelNumber,
            properties: [.read],
            value: Data(P2PGPS.SenderPlatform.ios.modelNumber.utf8),
            permissions: [.readable]
        )
        let firmware = CBMutableCharacteristic(
            type: BLEUUID.firmwareRevision,
            properties: [.read],
            value: Data(P2PGPS.firmwareRevision.utf8),
            permissions: [.readable]
        )
        let deviceInformation = CBMutableService(type: BLEUUID.deviceInformationService, primary: true)
        deviceInformation.characteristics = [manufacturer, model, firmware]
        self.deviceInformationService = deviceInformation

        manager.add(service)
        manager.add(deviceInformation)
        log.info("GATT サービスを登録しました")
    }

    private func beginAdvertising() {
        guard manager.state == .poweredOn else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEUUID.service],
            CBAdvertisementDataLocalNameKey: localName,
        ])
    }

    private func notifyIfSubscribed(_ data: Data, characteristic: CBMutableCharacteristic?) {
        guard let characteristic, subscriberCount > 0 else { return }
        let delivered = manager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        if !delivered {
            // The transmit queue is full; the next update will carry the newer
            // value, so dropping this one is correct for a 1 Hz stream.
            log.debug("notify キューが満杯のため送信をスキップ (\(characteristic.uuid))")
        }
    }

    private func updateState() {
        if !isBluetoothAvailable {
            state = .poweredOff
        } else if subscriberCount > 0 {
            state = .subscribed(count: subscriberCount)
        } else if isAdvertising {
            state = .advertising
        } else {
            state = .idle
        }
    }

    private func reportError(_ message: String) {
        lastError = message
        log.error(message)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension SenderPeripheral: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        isBluetoothAvailable = peripheral.state == .poweredOn
        switch peripheral.state {
        case .poweredOn:
            log.info("Bluetooth が利用可能になりました（ペリフェラル）")
            if pendingAdvertising {
                if service == nil {
                    addServices()
                } else if !peripheral.isAdvertising {
                    beginAdvertising()
                }
            }
        case .poweredOff:
            reportError("Bluetooth がオフです。設定から Bluetooth をオンにしてください。")
        case .unauthorized:
            reportError("Bluetooth の使用が許可されていません。設定 > プライバシーとセキュリティ > Bluetooth で許可してください。")
        case .unsupported:
            reportError("このデバイスは BLE ペリフェラルに対応していません。")
        case .resetting, .unknown:
            log.warning("Bluetooth の状態が不安定です (state=\(peripheral.state.rawValue))")
        @unknown default:
            log.warning("未知の Bluetooth 状態です (state=\(peripheral.state.rawValue))")
        }
        updateState()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            reportError("GATT サービスの登録に失敗しました: \(error.localizedDescription)")
            return
        }
        log.info("GATT サービスを登録しました: \(service.uuid)")
        if pendingAdvertising, !peripheral.isAdvertising {
            beginAdvertising()
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            isAdvertising = false
            reportError("アドバタイズを開始できませんでした: \(error.localizedDescription)")
        } else {
            isAdvertising = true
            log.info("アドバタイズを開始しました: \(localName)")
        }
        updateState()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let characteristic = request.characteristic
        let data: Data
        if characteristic.uuid == BLEUUID.location {
            data = lastLocationData
        } else if characteristic.uuid == BLEUUID.status {
            data = lastStatusData
        } else if characteristic.uuid == BLEUUID.extended {
            data = lastExtendedData
        } else if let value = characteristic.value {
            data = value
        } else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
            return
        }

        guard request.offset >= 0, request.offset <= data.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            defer { peripheral.respond(to: request, withResult: .success) }
            guard request.characteristic.uuid == BLEUUID.control else { continue }
            guard let data = request.value else { continue }

            do {
                let command = try ControlCommand.decode(data)
                lastControlCommand = command
                log.info("Control 受信: \(command)")
                onControlCommand?(command)
            } catch let error as ControlCommandError {
                log.warning("不正な Control コマンド: \(error)")
                onControlError?(error)
            } catch {
                log.warning("Control コマンドの解釈に失敗: \(error)")
                onControlError?(.unknownOpcode(data.first ?? 0))
            }
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscribedCentralIDs.insert(central.identifier)
        subscriberCount = subscribedCentralIDs.count
        log.info("セントラルが購読を開始しました (\(characteristic.uuid), 合計 \(subscriberCount))")
        updateState()
        onSubscribersChanged?(subscriberCount)
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscribedCentralIDs.remove(central.identifier)
        subscriberCount = subscribedCentralIDs.count
        log.info("セントラルが購読を終了しました (\(characteristic.uuid), 合計 \(subscriberCount))")
        updateState()
        onSubscribersChanged?(subscriberCount)
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // The queue drained; the next scheduled update will go through.
    }
}
