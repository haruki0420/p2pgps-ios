# P2P GPS for iOS / iPadOS

iPhone（または Android）で取得した GPS 位置を **BLE GATT** で iPad に転送し、iPad 上で「その位置にいる」ように位置情報を反映するアプリです。クラウドを介さない P2P で、座標は端末外に送りません。

- **Sender（iPhone）**: CoreLocation で現在地を取得し、BLE ペリフェラルとして 20 bytes の Location Packet を 1 Hz で notify します。
- **Receiver（iPad）**: BLE セントラルとして受信し、MapKit で表示しながら、[StikDebug](https://github.com/StikDebug/StikDebug) 由来の位置シミュレーションエンジン（[TLocation](https://github.com/truongkma/t-location) から移植）で iPad 自身の位置を固定します。
- **Mac 不要**: [xtool](https://github.com/xtool-org/xtool) で Linux / WSL からビルドし、SideStore 等でサイドロードします。

> 位置注入エンジンは AGPL-3.0 の派生コードを含むため、本リポジトリは **AGPL-3.0** です。帰属は [NOTICE](NOTICE) を参照してください。

## 主な機能

1. **プロトコル v1 の厳密な実装**
   - 128-bit UUID、20 bytes Location Packet、8 bytes Extended Location、Control / Status を仕様どおりに encode / decode。
   - 受信側の検証（長さ・バージョン・予約ビット・座標範囲・Null Island・sequence 巻き戻り・stale）を実装。
   - 仕様 §10 のテストベクタを XCTest で検証（macOS で `swift test`）。
2. **Receiver（iPad）**
   - ステータスレール（接続 LED・送信元名・最終受信・電波・精度）。
   - フルブリード地図にクロスヘア + レンジリング、軌跡はパイン色のライン。
   - リードアウトプレートに緯度・経度（等幅・タブラー数字）と標高 / 精度 / 速度 / 更新。
   - 52pt の「位置情報を反映」トグル。注入中は上部にライブバナー（送信元・座標・停止）。
   - 自動再接続（許可した送信元のみ）、送信元一覧からの手動接続。
3. **Sender（iPhone）**
   - 現在地・精度・fix 品質、送信状態、BLE の 3 状態（アドバタイズ / 購読 / 送信）表示。
   - 52pt の「送信を開始 / 停止」。バックグラウンド維持の説明。
   - Control（START / STOP / SET_INTERVAL / REQUEST_FIX / SET_EXTENDED / RESET）に応答し、Status を notify。
4. **位置注入（TLocation 移植）**
   - pairing file のインポート（Files ピッカー）、`PairingFileStore` に 0600 で保存。
   - Developer Disk Image のダウンロード / 再取得 / マウント（`image_mounter_mount_personalized_with_callback_rsd`）。
   - LocalDevVPN 経由の RSD トンネル（`tunnel_create_rppairing` → `remote_server_connect_rsd` → `location_simulation_new/set/clear`）。
   - 5 秒ごとの再送でシミュレーションを維持。停止時は `clear`。
   - 埋め込みエンジンが使えない場合の `tlocation://` URL スキーム委譲モード。
5. **設定 / 診断**
   - Settings: pairing file、DDI、LocalDevVPN への導線、ターゲット IP（既定 `10.7.0.1`）、自動再接続、送信間隔、Extended、ログ桁数。
   - Diagnostics: 受信パケット hex、Status / Extended hex、FFI セッション状態、トンネル / DDI 状態、メモリ内ログの共有。

## ディレクトリ構成

```text
p2pgps-ios/
├── Package.swift                # SwiftPM（library product P2PGPSApp + C target idevice）
├── xtool.yml                    # xtool 設定（bundleID / product / Info.plist / icon / resources）
├── project.yml                  # XcodeGen（CI の Xcode リンク検証用）
├── PRODUCT.md / DESIGN.md       # 正本はリポジトリルートの共通版。ここは iOS 実装メモ
├── Resources/                   # アプリアイコン（PNG）
├── Vendor/idevice/              # include/ に idevice.h + module.modulemap（MIT）。.a は fetch スクリプトで取得
├── scripts/
│   ├── fetch-vendor.sh          # libidevice_ffi.a の取得 + SHA-256 検証（macOS/Linux/WSL）
│   └── fetch-vendor.ps1         # 同（Windows PowerShell）
├── Sources/
│   ├── P2PGPSProtocol/          # 純粋 Swift: UUID / LocationPacket / Extended / Control / Status / 検証
│   ├── P2PGPSCore/              # GPSFix / FixFilter / AppSettings / LogStore / AppRole（Foundation のみ）
│   ├── P2PGPSBLE/               # CoreBluetooth: ReceiverCentral / SenderPeripheral
│   ├── P2PGPSLocation/          # CoreLocation: SenderLocationService / BackgroundKeepAlive
│   ├── P2PGPSInjection/         # TLocation 移植: FFI / pairing file / DDI / Tunnel / 位置注入 / URL スキーム
│   └── P2PGPSApp/               # SwiftUI: @main / Home / Receiver / Sender / Settings / Diagnostics
├── Tests/P2PGPSProtocolTests/   # 仕様 §10 のテストベクタ + Core のテスト
├── docs/                        # setup-linux / receiver-setup / architecture / protocol / design
├── wiki/                        # GitHub Wiki 用 Markdown
└── .github/workflows/ci.yml     # macOS ランナー: swift test → iOS クロスビルド → xcodebuild
```

## ビルド

### 1. ベンダーライブラリの取得（必須）

`libidevice_ffi.a`（約 92.6 MB、arm64 iOS 専用）はリポジトリに含めていません。TLocation の固定コミットから取得し、SHA-256 を検証します。

```bash
# macOS / Linux / WSL
bash scripts/fetch-vendor.sh

# Windows PowerShell
pwsh -File scripts/fetch-vendor.ps1
```

期待する SHA-256: `6524066D54EF23E00D46445C04DFC694E180196D54119D718F68434FA225BE35`

### 2. テスト（macOS / Linux の Swift ツールチェーン）

```bash
swift test
```

`P2PGPSProtocol` / `P2PGPSCore` は Foundation のみに依存するため、macOS で XCTest が動きます。iOS 専用ターゲットは `#if canImport(UIKit)` でガードしてあり、`swift test` がパッケージ全体をビルドしても壊れません。

### 3. xtool でビルド（Linux / WSL、Mac 不要）

[xtool](https://github.com/xtool-org/xtool) と iOS SDK のセットアップは [docs/setup-linux.md](docs/setup-linux.md) を参照してください。

```bash
xtool dev build     # .app をビルド
xtool dev run       # 接続中の実機へインストール・起動
```

### 4. Xcode（Mac がある場合）

```bash
xcodegen generate
open P2PGPS.xcodeproj
```

`project.yml` は CI のリンク検証用に、SwiftPM の全ソースを単一モジュールとしてコンパイルします（TLocation の Xcode プロジェクトと同じ構成）。ソース側は `#if SWIFT_PACKAGE` で cross-module import を切り替えているため、両方のビルドで同じファイルがそのまま通ります。

### Swift 6 と言語モード

- ツールチェーンは **Swift 6**（`swift-tools-version: 6.0`）です。
- `P2PGPSProtocol` / `P2PGPSCore` は **Swift 6 言語モード**（strict concurrency）でビルドします。値型中心で `Sendable` を明示しています。
- `P2PGPSBLE` / `P2PGPSLocation` / `P2PGPSInjection` / `P2PGPSApp` は **Swift 5 言語モード**です。TLocation から移植したエンジン（静的ハンドル・`Thread`・`DispatchQueue`）を変更せずに保つための判断で、`Package.swift` の `swiftSettings: [.swiftLanguageMode(.v5)]` で指定しています。
- XcodeGen の検証ビルドも Swift 5 言語モード（`SWIFT_VERSION: 5.0`）です。

## デザイン

UI の視覚世界・トークン・anti-slop ルールの正本はリポジトリルートの [`DESIGN.md`](DESIGN.md)（プロダクト事実は [`PRODUCT.md`](PRODUCT.md)）です。iOS 実装への落とし込みは [`docs/design.md`](docs/design.md) に記録しています。

- 視覚世界は「測量標（benchmark）」。地図と座標が主役の計測器で、カードの山・グラデーション・影・絵文字アイコンは使いません。
- 色は paper / surface / ink / line / pine / live / amber / danger のセマンティックトークン（Light/Dark 両対応、`Color` extension で実装）。
- 座標は SF Mono（monospaced）の tabular 数字で画面上最も大きく表示。状態は色だけでなくアイコン + テキストで示します。
- 実機・Simulator が無いため、レンダリング検証（Dynamic Type / Dark Mode / Reduce Motion）は未実施です。

## iPad（Receiver）のセットアップ

位置注入には次の 4 つが必要です。詳細手順は [docs/receiver-setup.md](docs/receiver-setup.md) を参照してください。

1. **Developer Mode** を有効化（設定 > プライバシーとセキュリティ > デベロッパモード）。
2. **LocalDevVPN** をインストールして接続（iPad 自身を `10.7.0.1` としてループバック）。
3. **pairing file**（`.mobiledevicepairing`）を用意し、アプリの設定から読み込む。
4. **Developer Disk Image (DDI)** を設定画面からダウンロードしてマウント。

受信側の手順:

1. アプリを起動し「受信する」を選ぶ。
2. 「スキャン開始」→ 一覧から `P2PGPS-IOS-XXXX` を選ぶ。
3. 座標が表示されたら「位置情報を反映」を ON にする（既定 OFF）。
4. 注入中は上部バナーに送信元・座標・停止ボタンが常時表示されます。

## プロトコル

仕様の正本は `p2pgps-protocol` リポジトリの `spec/protocol-v1.md` です。実装上の注意は [docs/protocol.md](docs/protocol.md) にまとめています。

- Service `B1E5A000-9C3D-4E7A-8F20-1A2B3C4D5E6F`
- Location Packet: 20 bytes、`version=0x01`、lat/lon は度 × 10^7 の int32 LE
- 検証: 長さ 20 / version 1 / flags bit7 = 0 / lat ±900,000,000 / lon ±1,800,000,000 / Null Island は無効扱い
- Control: START / STOP / SET_INTERVAL / REQUEST_FIX / SET_EXTENDED / RESET（未知 opcode は無視して `last_error=1`）
- Status: 8 bytes、状態変化 + 10 秒ハートビートで notify

## テストと CI

`.github/workflows/ci.yml`（`macos-15`）:

1. `swift test` — Protocol / Core のユニットテスト（macOS）
2. `bash scripts/fetch-vendor.sh` — ベンダーライブラリ取得 + SHA-256 検証
3. `swift build --triple arm64-apple-ios17.0 --sdk $(xcrun --sdk iphoneos --show-sdk-path)` — iOS SDK に対する全モジュールのクロスビルド
4. `brew install xcodegen` → `xcodegen generate` → `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` — Xcode でのコンパイルと静的リンクまで検証

## 既知の制約

- **実機・シミュレータでの動作検証は未実施**です。この開発環境には Xcode / Swift / iOS 実機がなく、CI はコンパイルとリンクのみを保証します。BLE・位置注入・UI の実動作は実機で確認してください。
- 位置注入は Apple の Developer Disk Image・LocalDevVPN・pairing file を必要とし、TLocation と同一の idevice FFI に固定しています。iOS の更新で壊れる可能性があります。
- v1 は **同時 1 台接続**、ボンディング / 認証なし（Just Works 相当）。近距離の第三者が偽の位置を送れるため、自動接続は許可した送信元のみ、注入は既定 OFF、注入中は常時バナー表示としています。
- 実機での UI 確認（Dynamic Type / Dark Mode / Reduce Motion）は未実施です。
- `libidevice_ffi.a` は arm64 iOS 専用です。macOS ネイティブビルドではリンクしません（`swift test` 用にリンカフラグを iOS のみに限定）。

## ライセンスと帰属

- 本リポジトリ: **AGPL-3.0**（[LICENSE](LICENSE)）
- 上流: StikDebug / TLocation（AGPL-3.0）、idevice（MIT）、xtool（MIT）。詳細は [NOTICE](NOTICE)。
- プロトコル仕様と Python リファレンス実装（`p2pgps-protocol`）は MIT です。
