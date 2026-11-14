# Design（このリポジトリ固有の実装メモ）

> **正本はプロジェクト共通の [`DESIGN.md`](DESIGN.md)。**
> 視覚世界「測量標（benchmark）」、カラートークン、タイポグラフィ、レイアウト、
> モーション、コピー、anti-slop ルールは共通版が正。このファイルは iOS
> （SwiftUI）での実装対応だけを記録する。共通版と競合する記述はしない。

## 実装方針

- 共通版のトークンを `Sources/P2PGPSApp/Design/P2PTheme.swift` の `Color` extension
  として定義する（`Color(light:dark:)` ヘルパーで `@Environment(\.colorScheme)` に追従。
  Asset Catalog は xtool のリソース制約を避けるため使わない）。
- 既定の青 tint は使わない。`.tint(P2PColor.pine)` をルートに適用する。
- 影・グラデーション・ガラス風ブラーは使わない。階層は `line`（1px ヘアライン）と
  `surface` / `paper` の差で作る。
- アイコンは SF Symbols のみ。絵文字は使わない。
- 数値は `.monospacedDigit()`、座標は `.monospaced()`（SF Mono）。座標が画面で
  最も大きい数字になるよう `.title3` semibold 以上で表示する。
- 画面遷移は `NavigationStack` 標準。Home はカードではなく 2 行のロール選択。
  Settings / Diagnostics はネイティブ `Form` / `List`（inset grouped）。
- モーション: fix 到着時は座標の 120ms クロスフェードのみ。接続中 LED の
  opacity パルス 1.2s。`@Environment(\.accessibilityReduceMotion)` で無効化。
- 状態は色だけでなくアイコン + テキストで示す（LED + 状態文言 + 形）。

## 共通版との対応表

| 共通 DESIGN.md | iOS 実装 |
| :--- | :--- |
| Color tokens (light/dark) | `P2PColor`（`Color(light:dark:)`） |
| Status rail | `StatusRail`（`Views/Components/StatusRail.swift`） |
| Signal bars | `SignalBars`（4 本、`ink` / `line`） |
| Readout plate | `ReadoutPlate`（`surface`、上角丸 16、上辺 `line`） |
| Primary action 52pt | `PrimaryActionButton`（`pine` 塗り / 白文字 / 押下 0.98） |
| Live toggle 52pt | `LiveToggleButton`（OFF: surface+line、ON: liveFill+白+左 3pt live バー） |
| Live banner | `LiveBanner`（`liveFill` 10% 背景、左 3pt `live`、右「停止」） |
| Range rings / crosshair | `MapCrosshairOverlay`（`pine` 12% の 1px 円 ×3 + クロスヘア） |
| Trail | `MapPolyline`（`pine` 70%、3pt、丸キャップ） |
| 座標 VoiceOver | `accessibilityLabel("北緯 …, 東経 …")` |

## 検証状況

- コンパイル: CI（macOS ランナー）で検証予定。
- レンダリング: **未検証**（Simulator / 実機なし）。Dynamic Type・Dark Mode の
  実画面確認は未実施で、既知の制約として README に明記する。
