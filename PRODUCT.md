# Product（このリポジトリ固有の実装メモ）

> **正本はプロジェクト共通の PRODUCT.md（このリポジトリ外で管理）。**
> このファイルは `p2pgps-ios` の実装に固有の事実だけを追記する。プロダクトの
> 利用者・目的・位置づけ・原則は共通版を参照し、ここには重複して書かない。
> 共通版の `## Platform` は `adaptive`（iOS はこのリポジトリが担当）。

## Platform

ios（iPadOS を含む。iPad は Receiver、iPhone は Sender が既定）

## Stack

- Swift 6 toolchain / SwiftUI / iOS 17+、SwiftPM（library product `P2PGPSApp`）+ `xtool.yml`
- CoreBluetooth / CoreLocation / MapKit / Combine
- 位置注入: TLocation 由来の idevice FFI（`libidevice_ffi.a` を静的リンク、AGPL-3.0）
- CI: GitHub Actions `macos-15`（`swift test` + iOS クロスビルド + XcodeGen/xcodebuild）

## iOS 固有の制約

- 実機・シミュレータ・Xcode が開発環境に無い。**レンダリング検証は未実施**で、
  CI はコンパイルとリンクのみを保証する。実機確認は README の既知の制約に記載。
- 位置注入は Apple 非公開 API 相当。TLocation と同一の FFI に固定し、壊れた場合は
  `tlocation://` URL スキームへ委譲するフォールバックを設定で選べる。
- iPad 側は Developer Mode / LocalDevVPN / pairing file / DDI が前提。
- Sender は `bluetooth-peripheral` + `location`、Receiver は `bluetooth-central` +
  `location` の UIBackgroundModes を使う。Sender は送信中の位置情報セッションで、
  Receiver は注入 ON の間 `BackgroundKeepAlive`（低精度セッション）でバックグラウンド
  継続を担保する（注入 ON のまま画面を離れても維持。設定で無効化可。バッテリーとの
  トレードオフあり）。

## 画面と実装の対応

| 画面 | 実装ファイル | 共通 DESIGN.md の該当節 |
| :--- | :--- | :--- |
| Home（ロール選択） | `Sources/P2PGPSApp/Views/HomeView.swift` | Layout > Home |
| Receiver | `Sources/P2PGPSApp/Views/ReceiverView.swift` | Layout > Receiver |
| Sender | `Sources/P2PGPSApp/Views/SenderView.swift` | Layout > Sender |
| Settings | `Sources/P2PGPSApp/Views/SettingsView.swift` | Layout > Home / Settings / Diagnostics |
| Diagnostics | `Sources/P2PGPSApp/Views/DiagnosticsView.swift` | Layout > Home / Settings / Diagnostics |

トークンの iOS 実装（`Color` extension、フォント、コンポーネント）は
[`docs/design.md`](docs/design.md) に記録する。

## Evidence on Hand

- 仕様: プロトコル仕様 v1（`p2pgps-protocol`、v1 凍結）
- 全体アーキテクチャ: `docs/architecture.md`
- 参照実装: https://github.com/truongkma/t-location（AGPL-3.0, 上流コミット固定）
- 実機スクリーンショット・利用ログ: 無し（設計は推定）
