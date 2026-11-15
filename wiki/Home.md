# P2P GPS for iOS / iPadOS

iPhone の現在地を Bluetooth で iPad に送り、iPad の位置として使えるようにするアプリです。位置情報はクラウドを通らず、端末同士だけでやり取りします。

## 2 つの役割

| 役割 | 端末 | すること |
| :--- | :--- | :--- |
| 送信側 | iPhone | 現在地を iPad に送る |
| 受信側 | iPad | 送られてきた位置を地図に表示し、iPad の位置を書き換える |

## はじめかた

1. [Setup iPad](Setup-iPad) — iPad の準備（Developer Mode / LocalDevVPN / pairing file / DDI）
2. [Build](Build) — アプリのビルド
3. [Source](Source) — SideStore / AltStore での配布
4. [困ったとき](Troubleshooting)
5. [よくある質問](FAQ)

## できること

- 送信側: 現在地・精度・電池残量を表示し、送信の開始/停止ができる
- 受信側: 地図・軌跡・座標・精度を表示し、「位置情報を反映」で iPad の位置を書き換える
- 位置の書き換え中は画面上部にバナーを出し、止め忘れを防ぐ
- 設定で送信間隔（0.1〜5 秒）と「速度と向きも送る」を変更できる

## 注意

- iPad の位置を書き換えるには、Developer Mode・LocalDevVPN・pairing file・DDI が必要です。
- Bluetooth での位置の受け渡しと、iPad の位置の書き換えは Android 実機 + iPad で確認済みです。全画面 UI・Dynamic Type・Dark Mode は未確認です。
- 本アプリは AGPL-3.0 です。詳しくは [License](License) を参照してください。
