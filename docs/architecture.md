# iOS アプリ アーキテクチャ

`p2pgps-ios` は SwiftPM の 6 モジュール構成です。`P2PGPSProtocol` / `P2PGPSCore` は Foundation のみに依存し macOS でテストでき、残りは iOS 専用です（`#if canImport(UIKit)` でガードし、`swift test` がパッケージ全体をビルドしても壊れないようにしています）。

## 1. モジュールと依存関係

```
P2PGPSApp ──┬─▶ P2PGPSBLE ──┬─▶ P2PGPSCore ──▶ P2PGPSProtocol
            ├─▶ P2PGPSLocation ─┘
            └─▶ P2PGPSInjection ──▶ P2PGPSCore, idevice(C)
```

| モジュール | 責務 | 主な型 |
| :--- | :--- | :--- |
| `P2PGPSProtocol` | 仕様 v1 の純粋実装 | `P2PGPS`, `LocationPacket`, `ExtendedLocationPacket`, `ControlCommand`, `SenderStatus`, `SequenceTracker` |
| `P2PGPSCore` | プラットフォーム非依存のモデル | `GPSFix`, `FixFilter`, `AppSettings`, `SettingsStore`, `LogStore`, `AppRole` |
| `P2PGPSBLE` | CoreBluetooth | `ReceiverCentral`, `SenderPeripheral`, `SignalQuality` |
| `P2PGPSLocation` | CoreLocation | `SenderLocationService`, `BackgroundKeepAlive`, `DeviceBattery` |
| `P2PGPSInjection` | TLocation 移植の位置注入 | `LocationSimulationEngine`, `TunnelManager`, `MountingProgress`, `DeveloperDiskImageService`, `PairingFileStore`, `URLSchemeLocationFallback` |
| `P2PGPSApp` | SwiftUI アプリ | `P2PGPSiOSApp`（@main）, `RootView`, `HomeView`, `ReceiverView`, `SenderView`, `SettingsView`, `DiagnosticsView` |

`idevice` は `Vendor/idevice` の C ターゲット（公開ヘッダは `Vendor/idevice/include/` の `idevice.h` + `module.modulemap`）です。静的ライブラリ `libidevice_ffi.a` はリポジトリに含めず、`scripts/fetch-vendor.sh` が TLocation の固定コミットから取得して SHA-256 を検証します。

## 2. データフロー（Receiver）

1. `CBCentralManager` が Service UUID でスキャン → 接続 → サービス / キャラクタリスティック探索。
2. Status を read し、`START(interval)` を write（仕様 §5、再接続でも冪等）。
3. Location / Status / Extended を notify 購読。
4. 20 bytes を受信 → `LocationPacket.decode`（長さ・version・予約ビット・座標範囲を検証）。
5. `SequenceTracker` で巻き戻り / 欠落を分類（記録するが受理、仕様 §3.3）。
6. `FixFilter` で外れ値除去と精度重み付き平滑化。
7. `GPSFix` を地図・軌跡・リードアウトに反映。
8. 注入 ON のときだけ `LocationSimulationEngine.set(lat, lon)` を直列キューに投入。エンジンは 5 秒ごとに再送し、OFF で `clear`。

## 3. データフロー（Sender）

1. `CLLocationManager`（`kCLLocationAccuracyBest`、distanceFilter なし）で 1 Hz の fix を取得。
2. `GPSFix` → `LocationPacket(fix:sequence:)`（flags に VALID_FIX / ALTITUDE_VALID / SPEED_VALID / SIMULATED / CHARGING / LOW_BATTERY / MOVING を設定）。
3. `CBPeripheralManager` で Service を登録しアドバタイズ（`P2PGPS-IOS-XXXX`）。
4. 購読者がいる間、設定間隔で notify。Status は状態変化 + 10 秒ハートビート。
5. Control を受信したら状態機械を更新（START/STOP/SET_INTERVAL/REQUEST_FIX/SET_EXTENDED/RESET）。未知 opcode / 不正長は無視して `last_error` を設定。
6. 購読者が 0 になったら Idle に戻る（アドバタイズは継続、仕様 §7）。

## 4. 位置注入エンジン（TLocation 移植）

- `JITEnableContext`: アプリの長命な RSD トンネル（DDI マウント用）。`tunnel_create_rppairing` → `rsd_handshake`。
- `simulate_location`: 位置シミュレーション専用のトンネルを別途張り（エンドポイントは単一占有のため）、`remote_server_connect_rsd` → `location_simulation_new` → `location_simulation_set`。既存セッションがあれば `set` だけ呼ぶ。
- `clear_simulated_location`: `location_simulation_clear` → 300 ms 待ってからハンドル解放。
- すべての FFI 呼び出しは `LocationSimulationCommandQueue`（直列 `DispatchQueue`）上で実行。`LocationSimulationState` のハンドルはこのキューに閉じ込める。
- `LocationSimulationEngine` が UI 向けファサード。5 秒ごとの再送、状態の `@Published`、日本語エラーメッセージを担当。
- `URLSchemeLocationFallback`: 埋め込みエンジンが使えない場合に `tlocation://simulate-location?lat=..&lon=..` / `tlocation://clear-location` へ委譲。

## 5. 並行性

- `P2PGPSProtocol` / `P2PGPSCore` は Swift 6 言語モード。値型中心で `Sendable`。
- `P2PGPSBLE` / `P2PGPSLocation` / `P2PGPSInjection` / `P2PGPSApp` は Swift 5 言語モード。TLocation 由来のコード（静的ハンドル・`Thread`・`DispatchQueue`）をそのまま保つためです。
- CoreBluetooth のデリゲートは `queue: .main` で生成し、`@Published` の更新はメインスレッドに固定。
- 位置注入の FFI は直列キュー、状態の publish は `DispatchQueue.main.async`。

## 6. 2 つのビルドシステム

| | xtool（本番） | XcodeGen（CI 検証） |
| :--- | :--- | :--- |
| 入力 | `Package.swift` + `xtool.yml` | `project.yml` |
| モジュール | SwiftPM の 6 モジュール | 全ソースを単一モジュール |
| クロスモジュール import | `#if SWIFT_PACKAGE` で有効 | 無効（同一モジュール） |
| リンク | `idevice` C ターゲットの `linkerSettings`（`-L.../Vendor/idevice -lidevice_ffi`） | `OTHER_LDFLAGS` / `LIBRARY_SEARCH_PATHS` |
| 用途 | Linux/WSL からの実ビルド | macOS ランナーでのコンパイル + リンク検証 |

## 7. バックグラウンド

- Receiver: `bluetooth-central` + `location`。BLE 受信と注入ループを維持するため、`BackgroundKeepAlive` が低精度の位置更新を回す。
- Sender: `bluetooth-peripheral` + `location`。CoreLocation の更新でアプリを起こし続け、fix 到着時に送信する（タイマーではなく fix 駆動なのでバックグラウンドでも止まりにくい）。
- 位置情報は「常に許可」を推奨（「使用中のみ」だとバックグラウンドで停止）。

## 8. テスト戦略

| 層 | 方法 |
| :--- | :--- |
| Protocol | XCTest。仕様 §10 のテストベクタ（東京駅・南極・Null Island・範囲外・未知バージョン・sequence 巻き戻り・Extended・Control 各 opcode・Status） |
| Core | XCTest。FixFilter の外れ値 / 平滑化、設定の既定値、ログの丸め |
| BLE | 実機必須。プロトコル層から分離し、状態機械は純粋ロジックとしてテスト可能な形にしている |
| 注入 | 実機必須。CI はコンパイルのみ。手順は docs/receiver-setup.md |
| CI | macOS ランナーで `swift test` → iOS クロスビルド → XcodeGen/xcodebuild リンク |
