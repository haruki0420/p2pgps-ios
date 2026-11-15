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
| `P2PGPSInjection` | TLocation 移植の位置注入 | `LocationSimulationEngine`, `TunnelManager`, `MountingProgress`, `DeveloperDiskImageService`, `PairingFileStore`, `RemotePairingPortResolver`, `URLSchemeLocationFallback` |
| `P2PGPSApp` | SwiftUI アプリ | `P2PGPSiOSApp`（@main）, `RootView`, `HomeView`, `ReceiverView`, `SenderView`, `SettingsView`, `DiagnosticsView` |

`idevice` は `Vendor/idevice` の C ターゲット（公開ヘッダは `Vendor/idevice/include/` の `idevice.h` + `module.modulemap`）です。静的ライブラリ `libidevice_ffi.a` はリポジトリに含めず、`scripts/fetch-vendor.sh` が StikDebug の固定コミット（iOS 26 の Remote Pairing 対応を含む idevice ビルド）から取得して SHA-256 を検証します。

## 2. データフロー（Receiver）

1. `CBCentralManager` が Service UUID でスキャン → 接続 → サービス / キャラクタリスティック探索。
2. Status を read し、`START(interval)` を write（仕様 §5、再接続でも冪等）。
3. Location / Status / Extended を notify 購読。
4. 20 bytes を受信 → `LocationPacket.decode`（長さ・version・予約ビット・座標範囲を検証）。
5. `SequenceTracker` で巻き戻り / 欠落を分類（記録するが受理、仕様 §3.3）。
6. `FixFilter` で外れ値除去と精度重み付き平滑化（stale は破棄せず、表示側の警告のみ。仕様 §3.3-7）。
7. `GPSFix` を地図・軌跡・リードアウトに反映。
8. 注入 ON のときだけ `LocationSimulationEngine.set(lat, lon)` を直列キューに投入。エンジンは 5 秒ごとに再送し、OFF で `clear`。注入中は `BackgroundKeepAlive` が低精度の位置更新でアプリの停止を防ぐ（§7）。

## 3. データフロー（Sender）

1. `CLLocationManager`（`kCLLocationAccuracyBest`、distanceFilter なし）で 1 Hz の fix を取得。
2. `GPSFix` → `LocationPacket(fix:sequence:)`（flags に VALID_FIX / ALTITUDE_VALID / SPEED_VALID / SIMULATED / CHARGING / LOW_BATTERY / MOVING を設定）。
3. `CBPeripheralManager` で Service を登録しアドバタイズ（`P2PGPS-IOS-XXXX`）。
4. 購読者がいる間、設定間隔で notify。Status は状態変化 + 10 秒ハートビート。
5. Control を受信したら状態機械を更新（START/STOP/SET_INTERVAL/REQUEST_FIX/SET_EXTENDED/RESET）。未知 opcode / 不正長は無視して `last_error` を設定。
6. 購読者が 0 になったら Idle に戻る（アドバタイズは継続、仕様 §7）。

## 4. 位置注入エンジン（TLocation 移植）

- `JITEnableContext`: アプリの長命な RSD トンネル（DDI マウント用）。`tunnel_create_rppairing` → `rsd_handshake`。`TunnelManager.start()` も `LocationSimulationCommandQueue` に載せ、シミュレーションのハンドシェイクと直列化する。
- `simulate_location`: 位置シミュレーション専用のトンネルを別途張り（エンドポイントは単一占有のため）、`remote_server_connect_rsd` → `location_simulation_new` → `location_simulation_set`。既存セッションがあれば `set` だけ呼ぶ。
- `clear_simulated_location`: `location_simulation_clear` → 300 ms 待ってからハンドル解放。セッションが無いときは成功扱い（L-6）。
- すべての FFI 呼び出しは `LocationSimulationCommandQueue`（直列 `DispatchQueue`）上で実行。`LocationSimulationState` のハンドルはこのキューに閉じ込める。DDI のマウントチェック / pairing file 読み取り / `mountPersonalDDI` も `MountingProgress` 経由で同じキューに載せる（main スレッドで FFI を呼ばない）。
- `LocationSimulationEngine` が UI 向けファサード。5 秒ごとの再送、状態の `@Published`、日本語エラーメッセージを担当。トンネル系の失敗（providerCreate / remoteServer）では `markTunnelDisconnected()` を呼び、次回フォアグラウンドで再構築できるようにする。
- **ライフサイクル（TLocation 移植）**: アプリが background → active に戻ったとき、注入セッションが継続していなければ `startTunnelAfterPendingLocationCommands()` でトンネルを再構築する。セッションが継続中の場合は `LocationSimulationSession` の session-ended 通知を待ってから再構築する（単一占有エンドポイントを奪わないため）。
- **ON → OFF の順序保証（R-1）**: `set()` は FFI をキューに積むだけで `isSimulating` は完了時に初めて true になる。そのため `clear()` は「セッションが無い」と判断しても**必ず FFI clear をキューに積む**（no-session は成功扱い）。各操作は世代番号（`operationGeneration`）を持ち、キューの先頭と main の完了時に「自分が最新か」を再確認する。古い `set` は FFI を呼ばずに捨てるため、「注入 ON → 直後 OFF」でもデバイス側にセッションは残らない。
- `URLSchemeLocationFallback`: 埋め込みエンジンが使えない場合に `tlocation://simulate-location?lat=..&lon=..` / `tlocation://clear-location` へ委譲。`canOpenURL` で TLocation の有無を確認し、1 秒に 1 回へ間引く。`UIApplication.open` の完了で成功/失敗を反映し、失敗時は注入状態を解除してエラー表示する（R-6）。委譲ログに座標は出さない（プライバシー）。**バックエンド切替（R-15）**: 注入 ON のまま設定を切り替えた場合は、使用済みのバックエンドを個別に clear してから新しいバックエンドで再開する。注入 OFF / 切断時も「要求したバックエンド」を単位に clear するため、切替後に片方のセッションが残らない。
- **DDI のサプライチェーン**: `DeveloperDiskImageService` は `doronz88/DeveloperDiskImage` の固定コミット `a1020f81b6429f5ce40408cbe21c690512b613b5` から取得し、3 ファイルすべてを SHA-256 で検証する。不一致は削除してエラー表示。再取得は全ファイルを一時名で取得して検証後に置換する。
- **pairing file の保護（R-2）**: Application Support/Pairing に 0600 + `FileProtectionType.completeUntilFirstUserAuthentication` + バックアップ除外で保存する。`.complete` ではなく「初回ロック解除後」にしているのは、ロック中にセッションを再構築する際 `rp_pairing_file_read` がファイルを読む必要があるため。属性設定は `prepareURLOnce()` で初回/変更時のみ行う（R-7）。
- **`remote_server` ハンドルの所有権（M6）**: Rust 実装の `location_simulation_new` は `RemoteServerHandle` を借用するだけで所有権を取らないことを確認済み。`LocationSimulationState` がハンドルを保持し、`cleanup()` で location simulation → remote server の順に free する（セッションごとのソケットリークを修正）。

## 5. 並行性

- `P2PGPSProtocol` / `P2PGPSCore` は Swift 6 言語モード。値型中心で `Sendable`。
- `P2PGPSBLE` / `P2PGPSLocation` / `P2PGPSInjection` / `P2PGPSApp` は Swift 5 言語モード。TLocation 由来のコード（静的ハンドル・`DispatchQueue`）をそのまま保つためです。テストターゲットも Swift 5 言語モード（XCTest と SwiftPM の `Bundle.module` アクセサが strict concurrency 前提でないため）。
- CoreBluetooth のデリゲートは `queue: .main` で生成し、`@Published` の更新はメインスレッドに固定。
- 位置注入の FFI は直列キュー、状態の publish は `DispatchQueue.main.async`。`JITEnableContext` のハンドル操作（`startTunnel` / `ensureTunnel` / `invalidateTunnel`）も同じ直列キュー上でのみ行う。
- `LocationSimulationEngine` の操作世代番号（`operationGeneration`）は main で更新し FFI キューから参照するため、`NSLock` で保護する（R-1）。

## 6. 2 つのビルドシステム

| | xtool（本番） | XcodeGen（CI 検証） |
| :--- | :--- | :--- |
| 入力 | `Package.swift` + `xtool.yml` | `project.yml` |
| モジュール | SwiftPM の 6 モジュール | 全ソースを単一モジュール |
| クロスモジュール import | `#if SWIFT_PACKAGE` で有効 | 無効（同一モジュール） |
| リンク | `idevice` C ターゲットの `linkerSettings`（`-L.../Vendor/idevice -lidevice_ffi`） | `OTHER_LDFLAGS` / `LIBRARY_SEARCH_PATHS` |
| 用途 | Linux/WSL からの実ビルド | macOS ランナーでのコンパイル + リンク検証 |

## 7. バックグラウンド

- Receiver: `bluetooth-central` + `location`。BLE 受信は `bluetooth-central` で起床できるが、注入の 5 秒再送は `DispatchSourceTimer` なので、iOS に suspend されると止まる。注入 ON の間は `ReceiverController` が `BackgroundKeepAlive`（低精度・`allowsBackgroundLocationUpdates`）を開始し、画面を閉じてもプロセスを維持する。**注入 ON の間は Receiver 画面を離れても keep-alive を維持する**（R-4）。停止は注入 OFF か、設定でバックグラウンド維持を OFF にしたとき。
- バッテリーとのトレードオフ: keep-alive は低精度（3 km）・`distanceFilter = CLLocationDistanceMax` で更新頻度は低いが、注入 ON の間は位置情報セッションが動き続ける。バッテリーを優先する場合は設定で OFF にできる（その場合、画面 OFF や長時間のバックグラウンドで注入が止まり得る）。
- Sender: `bluetooth-peripheral` + `location`。送信中は CoreLocation の更新でアプリを起こし続け、fix 到着時に送信する（タイマーではなく fix 駆動なのでバックグラウンドでも止まりにくい）。停止中は位置セッションを止める。
- 位置情報は「常に許可」を推奨（「使用中のみ」だとバックグラウンドで停止）。設定画面の「バックグラウンド維持（受信側）」で Receiver の keep-alive を無効化できる。
- フォアグラウンド復帰時は `RootView` が `ReceiverController.handleScenePhaseActive()` を呼び、注入セッションが無ければトンネルを再構築する（§4）。
- **既知の制約（R-8）**: アプリを再起動すると、前回のプロセスが残したデバイス側シミュレーションセッションはアプリのハンドルが無いため `clear()` では消せない。再起動後は注入 OFF の状態から始まり、デバイス側に前回の座標が残っている可能性がある（再起動・再ログインで解消）。
- **既知の制約（R-11）**: RSSI のポーリングは main run loop の `Timer` 依存のため、バックグラウンド中は SignalBars が古い値のままになり得る（表示のみの制約、注入には影響しない）。

## 8. テスト戦略

| 層 | 方法 |
| :--- | :--- |
| Protocol | XCTest。仕様 §10 の代表ベクタを Swift で直接検証し、加えて `p2pgps-protocol/tests/vectors/*.json` の手動ミラー（`Tests/P2PGPSProtocolTests/Vectors/`）を `Bundle.module` から読んで全ベクタの encode / decode / validate を検証する |
| Core | XCTest。FixFilter の外れ値 / 平滑化、設定の既定値、ログの丸め |
| BLE | 実機必須。プロトコル層から分離し、状態機械は純粋ロジックとしてテスト可能な形にしている |
| 注入 | 実機必須。CI はコンパイルのみ。手順は docs/receiver-setup.md |
| CI | macOS ランナーで `swift test` → iOS クロスビルド → XcodeGen/xcodebuild リンク |
