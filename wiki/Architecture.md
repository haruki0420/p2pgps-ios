# アーキテクチャ

## 全体像

```
iPhone (Sender)                         iPad (Receiver)
┌──────────────────────┐   BLE GATT    ┌──────────────────────────────┐
│ CoreLocation         │  Location 20B │ CoreBluetooth                │
│ CoreBluetooth        │ ────────────▶ │ MapKit / 軌跡 / リードアウト │
│ peripheral           │ ◀──────────── │ central                      │
└──────────────────────┘  Control/Status└──────────────┬───────────────┘
                                                       │ idevice FFI
                                                       ▼
                                        ┌──────────────────────────────┐
                                        │ TLocation 由来の注入エンジン │
                                        │ pairing file / DDI / Tunnel  │
                                        │ location_simulation_set()    │
                                        └──────────────────────────────┘
```

## モジュール

| モジュール | 責務 |
| :--- | :--- |
| `P2PGPSProtocol` | UUID・Location Packet・Extended・Control・Status・検証（Foundation のみ） |
| `P2PGPSCore` | `GPSFix`・`FixFilter`・設定・ログ・ロール（Foundation のみ） |
| `P2PGPSBLE` | `ReceiverCentral`（CBCentralManager）/ `SenderPeripheral`（CBPeripheralManager） |
| `P2PGPSLocation` | `SenderLocationService`（CoreLocation）/ `BackgroundKeepAlive` |
| `P2PGPSInjection` | TLocation 移植: idevice FFI・pairing file・DDI・Tunnel・位置注入・URL スキーム |
| `P2PGPSApp` | SwiftUI: Home / Receiver / Sender / Settings / Diagnostics |

`P2PGPSProtocol` / `P2PGPSCore` は macOS でもビルド・テスト可能です。iOS 専用コードは `#if canImport(UIKit)` でガードしています。

## Receiver のデータフロー

1. スキャン（Service UUID フィルタ）→ 接続 → サービス探索
2. Status read + START write（再接続でも冪等）
3. Location / Status / Extended を notify 購読
4. `LocationPacket.decode` → 検証 → `SequenceTracker` → `FixFilter`
5. 地図・軌跡・リードアウトへ反映
6. 注入 ON のときだけ `LocationSimulationEngine.set()`（直列キュー、5 秒ごとに再送）

## Sender のデータフロー

1. CoreLocation（最高精度・distanceFilter なし）で 1 Hz
2. `LocationPacket(fix:sequence:)` を生成
3. 購読者がいる間、設定間隔で notify
4. Control に応答して状態機械を更新、Status を notify
5. 購読者が 0 になったら Idle（アドバタイズは継続）

## 位置注入エンジン

- `JITEnableContext`: DDI マウント用の長命トンネル
- `simulate_location`: 注入専用トンネル → `remote_server_connect_rsd` → `location_simulation_new/set`
- `clear_simulated_location`: `location_simulation_clear` → 300 ms 待って解放
- すべての FFI は直列 `DispatchQueue` 上で実行（RSD エンドポイントは単一占有）
- 失敗時は `tlocation://` URL スキームへ委譲可能

## ビルド

- 本番: SwiftPM + xtool（`Package.swift` / `xtool.yml`）
- CI: XcodeGen + xcodebuild（`project.yml`、単一モジュールでコンパイル + リンク検証）

詳細は [docs/architecture.md](https://github.com/haruki0420/p2pgps-ios/blob/main/docs/architecture.md) を参照してください。
