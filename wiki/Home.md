# P2P GPS for iOS / iPadOS

iPhone（または Android）の現在地を **BLE** で iPad に送り、iPad 上で「その位置にいる」ように位置情報を反映するアプリです。クラウドを介さず、座標は端末外に送りません。

## 2 つの役割

| 役割 | 端末 | すること |
| :--- | :--- | :--- |
| **Sender（送信）** | iPhone | 現在地を 1 Hz で BLE notify |
| **Receiver（受信）** | iPad | 受信・地図表示・位置情報の反映（注入） |

## はじめかた

1. [はじめかた（Getting Started）](Getting-Started) — ビルドとインストール
2. [iPad のセットアップ](Getting-Started#ipad-receiver-のセットアップ) — Developer Mode / LocalDevVPN / pairing file / DDI
3. [プロトコル](Protocol) — BLE GATT 仕様 v1 の実装
4. [アーキテクチャ](Architecture) — モジュール構成とデータフロー
5. [トラブルシューティング](Troubleshooting)
6. [FAQ](FAQ)

## 主な機能

- **プロトコル v1 の厳密な実装**: 20 bytes Location Packet、8 bytes Extended、Control / Status、受信側検証（範囲・Null Island・sequence 巻き戻り）。stale（±24 時間超）は破棄せず表示側の警告のみ。
- **Receiver**: ステータスレール、クロスヘア + レンジリングの地図、軌跡、リードアウトプレート、52pt の注入トグル、注入中のライブバナー、実測 RSSI、自動再接続（ユーザー切断は再接続しない）、注入中のバックグラウンド維持。
- **Sender**: 現在地・精度・fix 品質、BLE 3 状態、52pt の送信トグル、送信中のバックグラウンド継続。
- **位置注入**: TLocation 由来の idevice FFI エンジン（pairing file / DDI / RSD トンネル / location_simulation）。DDI は固定コミット + SHA-256 検証。`tlocation://` URL スキームへの委譲も可能。
- **設定 / 診断**: pairing file、DDI、LocalDevVPN、ターゲット IP、送信間隔、バックグラウンド維持（受信側）、ログ桁数、受信 hex、FFI 状態、ログ共有。

## 重要な制約

- **実機・シミュレータでの動作検証は未実施**です。CI はコンパイルとリンクのみを検証します。
- iPad の位置注入には **Developer Mode / LocalDevVPN / pairing file / DDI** が必須です。
- v1 は同時 1 台接続・認証なし。注入は既定 OFF、注入中は常時バナーを表示します。
- 本リポジトリは **AGPL-3.0** です（StikDebug / TLocation 派生）。帰属は [NOTICE](https://github.com/haruki0420/p2pgps-ios/blob/main/NOTICE) を参照してください。
