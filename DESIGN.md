# Design（このリポジトリ固有の実装メモ）

> **正本はプロジェクト共通の DESIGN.md（このリポジトリ外で管理）。**
> 視覚世界「測量標（benchmark）」、カラートークン、タイポグラフィ、レイアウト、
> モーション、コピー、anti-slop ルールは共通版が正。このファイルは iOS
> （SwiftUI）での実装対応だけを記録する。共通版と競合する記述はしない。
> 実装後の自己点検結果は [`wiki/Design.md`](wiki/Design.md) に詳述。

## 実装方針

- 共通版のトークンを `Sources/P2PGPSApp/Design/P2PTheme.swift` の `Color` extension
  として定義する（`Color(p2pLight:p2pDark:)` ヘルパーで `UIColor(dynamicProvider:)`
  を包み Light / Dark に自動追従。Asset Catalog は xtool のリソース制約を避けるため使わない）。
- 既定の青 tint は使わない。`.tint(P2PColor.pine)` をルートに適用する。
- 影・グラデーション・ガラス風ブラーは使わない。階層は `line`（1px ヘアライン）と
  `surface` / `paper` の差で作る。
- アイコンは SF Symbols のみ。絵文字は使わない。
- 数値は `.monospacedDigit()`、座標は `.monospaced()`（SF Mono）。座標が画面で
  最も大きい数字になるよう `.title3` semibold で表示する。
- 画面遷移は `NavigationStack` 標準。Home はカードではなく 2 行のロール選択。
  Settings / Diagnostics はネイティブ `Form` / `List`（inset grouped）。
- モーションは OS 標準の画面遷移、押下 0.98 スケール、地図カメラの
  `easeInOut 0.4s` のみ。**座標の 120ms クロスフェードは v1 では静的**（値は即時更新）。
  `@Environment(\.accessibilityReduceMotion)` で地図カメラのアニメーションを無効化する。
- **LED はパルスしない**（v1.0.1 で静的表示に統一）。接続状態は `StatusRail` が
  LED の右に状態テキスト（「接続済み」「スキャン中」「接続中」「切断中」「未接続」）を
  併記するため、色だけに依存しない。
- 状態は色だけでなくアイコン + テキストで示す（LED + 状態文言 + 形）。

## 共通版との対応表

| 共通 DESIGN.md | iOS 実装 |
| :--- | :--- |
| Color tokens (light/dark) | `P2PColor`（`Color(p2pLight:p2pDark:)`） |
| Status rail | `StatusRail`（LED + 状態テキスト + 最終受信/最終送信 + SignalBars + 精度） |
| Signal bars | `SignalBars`（4 本、`ink` / `line`。StatusRail に表示） |
| Readout plate | `ReadoutPlate`（`surface`、上角丸 16、上辺 `line`） |
| Primary action 52pt | `PrimaryActionButton`（`pine` 塗り / 文字色 `onPrimary` = paper: Light 白相当 / Dark paper / 押下 0.98） |
| Live toggle 52pt | `LiveToggleButton`（OFF: surface+line、ON: liveFill + `onLiveFill` 文字 + 左 3pt live バー） |
| Live banner | `LiveBanner`（`liveFill` 10% 背景、左 3pt `live`、右「停止」） |
| Range rings / crosshair | `MapCrosshairMarker`（`pine` 12% の 1px 円 ×3 + クロスヘア。**スクリーン空間の固定半径**で、v1 ではメートル換算しない） |
| Trail | `MapPolyline`（`pine` 70%、3pt、丸キャップ） |
| 座標 VoiceOver | 緯度行「北緯 …」/ 経度行「東経 …」を別々に読み上げ（`P2PFormat.spokenLatitude` / `spokenLongitude`） |

## 検証状況

- コンパイル: **CI（macOS ランナー）で検証済み**（`swift test` / iOS クロスビルド /
  XcodeGen + xcodebuild リンク）。
- BLE 購読・位置注入は Android 実機 + iPad で確認済みです。
- 全画面 UI・Dynamic Type・Dark Mode は **未確認**です。
