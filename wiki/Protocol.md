# プロトコル実装メモ

仕様の正本は `p2pgps-protocol` リポジトリの [`spec/protocol-v1.md`](https://github.com/haruki0420/p2pgps-protocol/blob/main/spec/protocol-v1.md)。ここでは `P2PGPSProtocol` の実装判断だけを記録します。

## 1. 定数

| 項目 | 値 | 実装 |
| :--- | :--- | :--- |
| Service | `B1E5A000-9C3D-4E7A-8F20-1A2B3C4D5E6F` | `P2PGPS.serviceUUID` |
| Location Packet | `B1E5A001-…` | `P2PGPS.locationCharacteristicUUID` |
| Control | `B1E5A002-…` | `P2PGPS.controlCharacteristicUUID` |
| Status | `B1E5A003-…` | `P2PGPS.statusCharacteristicUUID` |
| Extended | `B1E5A004-…` | `P2PGPS.extendedLocationCharacteristicUUID` |
| ローカルネーム | `P2PGPS-<PLATFORM>-<XXXX>` | `P2PGPS.localName(platform:suffix:)` |

UUID は文字列で保持し、CoreBluetooth への変換は `P2PGPSBLE.BLEUUID` が行います（`P2PGPSProtocol` を Foundation のみに保つため）。

## 2. Location Packet（20 bytes）

- ワイヤ値は `latitudeE7` / `longitudeE7`（int32）として保持し、度は計算プロパティ。丸め誤差なしで往復できます。
- エンコードは常に 20 bytes。受信側は長さが 20 でない時点で破棄。
- 検証（仕様 §3.3）:
  1. 長さ == 20
  2. `version == 0x01`
  3. `flags & 0x80 == 0`（予約ビット）
  4. `-900_000_000 <= lat <= 900_000_000`、`-1_800_000_000 <= lon <= 1_800_000_000`（度 × 10^7）
  5. `VALID_FIX == 1` でも `(0,0)` ±0.0001°（±1000 e7）は「無効な fix」として扱う（`isUsableFix == false`）
  6. sequence の巻き戻りは `SequenceTracker` が分類し、パケットは受理
  7. timestamp が ±24 時間を超える場合は `isStale` で警告表示（注入はユーザー設定に従う）
- `altitudeMeters` は `ALTITUDE_VALID` が立っているときだけ非 nil。`accuracy` / `speed` の 255 は「不明 / 255 以上」。
- 未送信時の read 応答は `LocationPacket.invalid`（version=1、flags=0、他 0）。

仕様 §3.3 の検証範囲（`±900_000_000` / `±1_800_000_000`）と実装・テストは一致しています。

## 3. Extended Location Packet（8 bytes）

- `provider` の未知値は `.unknown` に丸める（情報フィールドのため破棄しない）。
- `battery_pct` / `satellites` / `vertical_accuracy_m` の 255、`course` の 65535 は「不明」。
- 受信側は Extended が無くても動作する（任意）。

## 4. Control Command

- 1 コマンド = 1 GATT write。応答は Status notify。
- デコードは opcode ごとに長さを厳密に検証:
  - START `0x01` + uint16 LE（3 bytes）
  - STOP `0x02`（1 byte）
  - SET_INTERVAL `0x03` + uint16 LE（3 bytes）
  - REQUEST_FIX `0x04`（1 byte）
  - SET_EXTENDED `0x05` + uint8（2 bytes）
  - RESET `0x7F`（1 byte）
- 未知 opcode（`AUTH 0x10` を含む）は `unknownOpcode`、長さ不一致は `badLength`、0 長は `empty`。送信側はこれらを無視して `last_error` を設定。
- `interval_ms` は仕様 §5.1（v1.0.1 で明確化）の**境界クランプ方式**:
  - `encoded()` は**生値**を書く（受信側 = iPad が書く値。例: `START(0)` は `010000`）。
  - 送信側は `resolvedIntervalMilliseconds` で正規化して適用する: `0` → 1000、`1`–`99` → 100、`100`–`60000` → そのまま、`60001`–`65535` → 60000。
  - `decode()` は生値を保持し、正規化は `resolvedIntervalMilliseconds` を読む側（送信側）が行う。
  - Status の `interval_ms` は正規化後の値（送信側が適用中の値）を返す。
- テストベクタ（`Tests/P2PGPSProtocolTests/Vectors/control.json`）は `hex`（生値）と `normalized_interval_ms`（適用値）を分離して検証する。

## 5. Status

- 8 bytes。状態変化（START/STOP/エラー/測位状態変化）と 10 秒ハートビートで notify。
- `state` の未知値は `.error`、`last_error` の未知値は `.internalError` に丸める。
- `battery_pct` は 0–100 のときだけ値あり（255 は不明）。

## 6. テストベクタ

テストは 2 層あります。

1. **`Tests/P2PGPSProtocolTests/ProtocolVectorTests.swift`** — Swift で仕様 §10 の代表ベクタを直接検証（高速・自己完結）。
2. **`Tests/P2PGPSProtocolTests/Vectors/*.json` + `ProtocolVectorJSONTests.swift`** — `p2pgps-protocol` の `tests/vectors/*.json` を**手動でコピーしたミラー**を `Bundle.module` から読み、encode / decode / validate を全ベクタで検証する。共有契約データを実際に読むことで、参照実装との乖離をテスト失敗として検出できる。

> CI で `p2pgps-protocol` を checkout する仕組みは未導入です。ベクタを更新するときは上流からコピーし直してください（`Vectors/README.md` 参照）。Android は現時点で値をハードコードしているため、3 実装が同じ JSON を読む状態にはまだなっていません（実装間の乖離検出は protocol リポジトリの `test_spec_consistency.py` の範囲）。

| ベクタ | 期待 |
| :--- | :--- |
| 東京駅 | `01 03 2A 00 48 86 44 15 52 C5 4E 53 03 00 05 00 00 52 17 69` |
| 南極 | `01 03 07 00 00 17 5B CA 00 2E B6 94 E2 FF 0C 00 00 52 17 69` |
| Null Island | デコード成功・`isUsableFix == false` |
| 範囲外緯度 | `latitudeOutOfRange` |
| 未知バージョン | `unsupportedVersion` |
| sequence 巻き戻り | `rewound(by:)`、パケットは受理 |
| Extended | `01 01 57 0C 39 30 08 00` |
| Control 各 opcode | 生値のバイト列（例: `START(0)` = `01 00 00`）+ `normalized_interval_ms` |
| Status | `01 01 E8 03 57 03 00 00` |

東京駅の期待バイトは仕様 §3.2 の hex と一致しています（`lat 356812360 = 0x15448648`）。

## 7. 実装上の注意

- 浮動小数点はワイヤに載せない。度への変換は表示・地図用のみ。
- `Data` の整数アクセスはリトルエンディアン明示のヘルパー（`ByteCodec`）経由。
- 受信側は「破棄するか受理するか」を型で表す: `LocationPacket.decode` は構造的に不正なら throw、Null Island は受理しつつ `isUsableFix == false`。
- **stale（タイムスタンプが ±24 時間を超える）は破棄しません**（仕様 §3.3-7）。`FixFilter` は stale を理由に reject せず、`GPSFix.isStale(now:)` を表示側の警告（ReceiverView の「送信側の時刻が 24 時間以上ずれています」）に使います。注入するかはユーザー設定に従います。
- 送信側は `LocationPacket(fix:sequence:extraFlags:)` で flags を自動設定。範囲外の座標は境界にクランプして「デコード不能なパケットを送らない」ことを保証。
