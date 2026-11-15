# iOS デザイン実装メモ

正本はプロジェクト共通の [Design](https://github.com/haruki0420/p2pgps/wiki/Design)（視覚世界「測量標（benchmark）」）。このファイルは SwiftUI 実装への落とし込みと、実装後の自己点検結果を記録します。

## 1. トークンの実装

`Sources/P2PGPSApp/Design/P2PTheme.swift`:

### Color

`Color(p2pLight:p2pDark:)` ヘルパーで `UIColor(dynamicProvider:)` を包み、`@Environment(\.colorScheme)` を介さずに Light / Dark を自動追従させています（Asset Catalog は xtool のリソース制約を避けるため不使用）。

| token | Light | Dark | 実装 |
| :--- | :--- | :--- | :--- |
| `paper` | `#F2F4F2` | `#0F1A1E` | `P2PColor.paper` |
| `surface` | `#FBFCFB` | `#16252A` | `P2PColor.surface` |
| `ink` | `#17252A` | `#E8EEEC` | `P2PColor.ink` |
| `inkSecondary` | `#55666A` | `#9FB0B2` | `P2PColor.inkSecondary` |
| `line` | `#C9D3CE` | `#2A3B40` | `P2PColor.line` |
| `pine` | `#1E6B5A` | `#6FBFA8` | `P2PColor.pine` |
| `live` | `#A8502E` | `#E08A5F` | `P2PColor.live` |
| `liveFill` | `#B85C38` | `#C96A42` | `P2PColor.liveFill` |
| `amber` | `#8A5A12` | `#E0B25C` | `P2PColor.amber` |
| `danger` | `#A32E24` | `#E0705F` | `P2PColor.danger` |

- 既定の青 tint は使わず、ルートで `.tint(P2PColor.pine)`。
- 塗りボタンの文字色は `onPrimary` = `paper`（root DESIGN.md の「Light 白相当 / Dark paper」に対応。実測 Light 5.75:1 / Dark 8.17:1）。`liveFill` 塗りは `onLiveFill`（Light 白 / Dark paper）を使う（§4 参照）。

### Typography

`P2PFont` はシステムテキストスタイルのみ。ハードコードした pt サイズはありません。

| 用途 | 実装 |
| :--- | :--- |
| 画面タイトル | `.title2` semibold |
| ロール行 | `.title3` semibold |
| 座標 | `.title3` **monospaced** semibold + `.monospacedDigit()` |
| 補助数値 | `.footnote` monospaced |
| hex / ログ | `.caption` monospaced |
| 本文・ラベル | `.body` / `.subheadline` |

### Spacing / Motion

`P2PSpacing`（gutter 16、rail 52、primary 52、corner 16/10、tap 44、hairline 1）。モーションは OS 標準の画面遷移、押下 0.98 スケール、地図カメラの `easeInOut 0.4s`（Reduce Motion で無効）のみです。

**LED はパルスしません**（root `DESIGN.md` の v1.0.1 更新に合わせて静的表示）。接続状態は `StatusRail` が LED の右に状態テキスト（「接続済み」「スキャン中」「接続中」「切断中」「未接続」）を併記するため、色だけに依存しません。

**座標の 120ms クロスフェードは v1 では静的**（値は即時更新）です。DESIGN.md の Motion のうち実装済みなのは地図カメラと押下フィードバックのみで、Reduce Motion は地図カメラのアニメーションを止めます。

## 2. コンポーネント対応

`Sources/P2PGPSApp/Design/Components.swift`:

| DESIGN.md | 実装 | 備考 |
| :--- | :--- | :--- |
| Status rail | `StatusRail` | `TimelineView(.periodic(by: 1))` で「最終受信 0.8 秒前」を更新。LED の右に状態テキスト（`statusText`）を併記。Sender では `lastEventLabel: "最終送信"` |
| Signal bars | `SignalBars` | 4 本 3×10pt、`ink` / `line`。`StatusRail` に表示（VoiceOver では状態テキストで代替し、バー自体は非表示） |
| Connection LED | `ConnectionLED` | 8pt。接続=pine、待機=amber、エラー=danger、未接続=inkSecondary 輪郭。**パルスなし（静的）**。色だけに依存しないよう状態テキストを併記 |
| Readout plate | `ReadoutPlate` | `surface`、上角丸 16、上辺 1px `line` |
| Coordinate row | `CoordinateRow` | `.title3` monospaced semibold、VoiceOver は緯度行「北緯 …」/ 経度行「東経 …」を別々に読み上げ |
| Metrics | `MetricItem` | 標高 / 精度 / 速度 / 更新 |
| Primary action | `PrimaryActionButton` | 52pt、`pine` 塗り、**文字色 = `onPrimary`（Light 白相当 / Dark paper）**、押下 0.98 |
| Live toggle | `LiveToggleButton` | 52pt。OFF=surface+line、ON=liveFill + **`onLiveFill` 文字** + 左 3pt live バー |
| Live banner | `LiveBanner` | safe area inset 上部、liveFill 10% 背景、左 3pt live、右「停止」 |
| Range rings / crosshair | `MapCrosshairMarker` | 地図上に 3 本のリング + クロスヘア。**スクリーン空間の固定半径（88/156/232 pt）**で、v1 ではメートル換算しない（正確な距離スケールが必要になったら `MapReader` / `MapProxy.convert` で実装） |
| Trail | `MapPolyline` | pine 70%、3pt、丸キャップ |
| Fix quality | `FixQualityBars` | Sender 用 4 セグメント |

## 3. 画面構成

- **Home** (`Views/HomeView.swift`): 2 行のロール選択（カードなし、ヘアライン区切り）。設定 / 診断への導線。`NavigationStack` + large title。
- **Receiver** (`Views/ReceiverView.swift`): StatusRail → フルブリード `Map`（クロスヘア + レンジリング + 軌跡）→ `ReadoutPlate`（座標 2 行 + 指標 + 52pt トグル）。注入中は `safeAreaInset(edge: .top)` に LiveBanner。
- **Sender** (`Views/SenderView.swift`): StatusRail → `ReadoutPlate`（座標 + 精度 + fix 品質）→ 状態テキスト → BLE 3 状態 → 52pt 主ボタン → 説明。
- **Settings / Diagnostics**: ネイティブ `Form` / `List`（inset grouped）。カードを作らない。

## 4. anti-slop チェックリスト結果

| 項目 | 結果 |
| :--- | :--- |
| クリーム背景 + セリフ見出し + テラコッタ | ✅ 未使用（paper はグレーグリーン寄り、フォントは SF のみ） |
| 近黒背景 + 単一の蛍光アクセント | ✅ 未使用（pine / live / amber / danger の 4 系統） |
| 同一角丸カードの並列・影の散布 | ✅ カードなし。影・グラデーション・ブラーなし。階層は `line` と `surface` の差のみ |
| ALL CAPS アイブロウ / `A · B · C` / `WORD — fragment` / `→` ボタン | ✅ 未使用（`P2PSectionHeader` は通常のラベル） |
| グラデーション・ガラス・絵文字アイコン | ✅ 未使用（SF Symbols のみ） |
| 01 / 02 / 03 の番号 | ✅ 未使用 |
| 座標が画面で最も大きい数字 | ✅ 座標は `.title3` monospaced semibold、他の数値は `.footnote` / `.caption` |
| 状態が色だけで伝わらない | ✅ LED + `StatusRail` の状態テキスト + シグナルバー / アイコン + テキスト（`bleItem`、`P2PErrorRow`） |
| タップ領域 44×44pt / Dynamic Type / Reduce Motion | ✅ 主要操作は 52pt、行は最低 44pt。システムテキストスタイル。Reduce Motion で地図カメラアニメーションを停止（LED は静的で動かない。座標クロスフェードは未実装） |

### 追加で確認した点

- **コントラスト（C-8）**: 塗りボタンの文字色はハードコードせずトークンで持つ。
  - `P2PColor.onPrimary` = `paper`（`PrimaryActionButton` の `pine` 塗り。root DESIGN の「Light 白 / Dark paper」に対応）: Light **5.75:1** / Dark **8.17:1**。
  - `P2PColor.onLiveFill`（`LiveToggleButton` ON の `liveFill` 塗り）: Light = white **4.54:1** / Dark = `paper` **4.74:1**。Light の `liveFill` に `paper` を載せると 4.11:1 で AA 未満になるため、`onLiveFill` を分けている。
  - `Color.white` をハードコードしないこと。Dark の `pine` は明るく、白文字だと **2.17:1** まで落ちる（Android の C-8 と同じ落とし穴）。
  - 補助テキストの `inkSecondary`: Light 5.44:1 / Dark 7.86:1（本文には使わない）。
- `inkSecondary` は本文ではなく補助ラベルのみ。
- 数値はすべて `.monospacedDigit()`。座標は `.minimumScaleFactor(0.65)` で Dynamic Type 大でも 1 行に収める。
- 空状態・エラー状態・権限不足状態を用意（`P2PEmptyState` / `P2PErrorRow` / SenderView の許可導線）。
- VoiceOver: 座標は緯度行「北緯 35.681236」/ 経度行「東経 139.767125」を別々に読み上げます（`P2PFormat.spokenLatitude` / `spokenLongitude`）。LED とシグナルバーは非表示（状態テキストで代替）、ボタンは動作を名指し。

## 5. 検証状況

- コンパイル: **CI（macOS ランナー）で検証済み**（`swift test` / iOS クロスビルド / XcodeGen + xcodebuild リンクのみ）。ローカルに Swift / Xcode / Simulator は無い。
- レンダリング: **未検証**。Dynamic Type XXL・Dark Mode・Reduce Motion の実画面確認は実機で行う必要があります。既知の制約として README に記載。
- 地図のレンジリングはスクリーン空間の固定半径（88/156/232 pt）で、メートル換算はしていません（v1 の既知の制約）。正確な距離スケールが必要になったら `MapReader` / `MapProxy.convert` で実装してください。
