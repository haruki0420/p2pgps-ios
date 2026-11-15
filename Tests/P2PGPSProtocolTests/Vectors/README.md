# 共有テストベクタ（手動ミラー）

このディレクトリの JSON は、プロトコル仕様の正本リポジトリ
[`p2pgps-protocol`](https://github.com/haruki0420/p2pgps-protocol) の
`tests/vectors/*.json`（MIT）を **手動でコピーしたミラー** です。

- 出典: `p2pgps-protocol/tests/vectors/`（`location.json` / `extended.json` /
  `control.json` / `status.json` / `sequences.json`）
- ライセンス: MIT（`p2pgps-protocol`）
- 読み込み: `Tests/P2PGPSProtocolTests/ProtocolVectorJSONTests.swift` が
  `Bundle.module` から読み、encode / decode / validate を検証します
  （SwiftPM の test target に `resources: [.copy("Vectors")]` を指定）。

## 同期のルール

- **CI で protocol リポジトリを checkout する仕組みは未導入**です。ベクタを
  更新するときは上流からコピーし直し、`swift test` を通してください。
- 上流の README のとおり、Python / Swift（このミラー）/ Kotlin（Android）の
  各実装が同じ内容のミラーを読んでいます（自動同期はありません）。Android も `ProtocolVectorTest` から
  JSON を読み込むため、実装間の乖離は各実装のテストで検出できます。
  手動ミラーのため、上流更新時の再同期は運用で担保します。

## `control.json` について（仕様 §5.1 / v1.0.1）

`control.json` は仕様 §5.1 の決定（**境界クランプ方式**）に合わせて、
「受信側が書く生値」と「送信側が適用する正規化値」を分離した形式です。

- `hex`: 生値の 1〜3 bytes（例: `START(0)` は `010000`）
- `expect.decoded.interval_ms`: デコードした生値
- `expect.decoded.normalized_interval_ms`: 送信側が適用する値
  （0→1000、1–99→100、100–60000→そのまま、60001–65535→60000）

`p2pgps-protocol` 側の `control.json` は §5.1 対応済み（`a8d482a`）で、この
ミラーは `3369460` で description まで同期済みです。上流が更新されたら
同じ手順で再同期してください。
