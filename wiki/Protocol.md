# プロトコル

P2P GPS BLE プロトコル v1 の実装メモです。仕様の正本は `p2pgps-protocol` リポジトリの `spec/protocol-v1.md` です。

## GATT プロファイル

| Characteristic | UUID | Properties | 方向 | 長さ |
| :--- | :--- | :--- | :--- | :--- |
| Service | `B1E5A000-9C3D-4E7A-8F20-1A2B3C4D5E6F` | — | — | — |
| Location Packet | `B1E5A001-…` | read, notify | Sender → Receiver | 20 bytes |
| Control | `B1E5A002-…` | write, write-without-response | Receiver → Sender | 1–3 bytes |
| Status | `B1E5A003-…` | read, notify | Sender → Receiver | 8 bytes |
| Extended Location | `B1E5A004-…` | read, notify | Sender → Receiver | 8 bytes |

- 送信側のローカルネーム: `P2PGPS-<PLATFORM>-<XXXX>`（例 `P2PGPS-IOS-7F3C`）。
- 20 bytes 固定なので BLE 4.0 の既定 MTU 23（ペイロード 20）でも分割不要です。

## Location Packet（20 bytes）

| Offset | Size | Field | 型 | 説明 |
| ---: | ---: | :--- | :--- | :--- |
| 0 | 1 | version | uint8 | `0x01` |
| 1 | 1 | flags | uint8 | bit0 VALID_FIX / bit1 ALTITUDE_VALID / bit2 SPEED_VALID / bit3 SIMULATED / bit4 CHARGING / bit5 LOW_BATTERY / bit6 MOVING / bit7 reserved(0) |
| 2 | 2 | sequence | uint16 LE | +1 ごと、65535 → 0 |
| 4 | 4 | latitude | int32 LE | 度 × 10^7 |
| 8 | 4 | longitude | int32 LE | 度 × 10^7 |
| 12 | 2 | altitude_m | int16 LE | 整数 m（無効時 0） |
| 14 | 1 | accuracy_m | uint8 | 255 = 不明 |
| 15 | 1 | speed_mps | uint8 | 255 = 不明 |
| 16 | 4 | timestamp | uint32 LE | Unix 秒 |

### 受信側の検証

1. 長さ == 20
2. `version == 0x01`
3. `flags & 0x80 == 0`
4. `-900_000_000 <= latitude <= 900_000_000` かつ `-1_800_000_000 <= longitude <= 1_800_000_000`
5. `VALID_FIX == 1` でも (0,0) ±0.0001° は無効扱い（Null Island 対策）
6. sequence の巻き戻りはログに記録するがパケットは受理
7. timestamp が ±24 時間を超える場合は stale として警告表示

## Control（受信側 → 送信側）

| opcode | 名称 | payload |
| ---: | :--- | :--- |
| `0x01` | START | uint16 LE interval_ms（0 = 1000、100–60000 にクランプ） |
| `0x02` | STOP | なし |
| `0x03` | SET_INTERVAL | uint16 LE interval_ms |
| `0x04` | REQUEST_FIX | なし |
| `0x05` | SET_EXTENDED | uint8 enabled |
| `0x7F` | RESET | なし |

未知 opcode は無視して Status の `last_error = 1`、不正長は `last_error = 2`。

## Status（8 bytes）

`version` / `state`（0=Idle, 1=Streaming, 2=Paused, 3=Error）/ `interval_ms` / `battery_pct` / `status_flags` / `last_error` / reserved。

状態変化時と 10 秒ごとのハートビートで notify します。

## テストベクタ

`swift test` で仕様 §10 のベクタを検証します（東京駅・南極・Null Island・範囲外・未知バージョン・sequence 巻き戻り・Extended・Control 各 opcode・Status）。

- `Tests/P2PGPSProtocolTests/ProtocolVectorTests.swift`: 代表ベクタを Swift で直接検証。
- `Tests/P2PGPSProtocolTests/Vectors/*.json`: `p2pgps-protocol` の共有ベクタの手動ミラーを `ProtocolVectorJSONTests.swift` が読み、全ベクタで encode / decode / validate を検証。

Control の `interval_ms` は仕様 §5.1 の境界クランプ方式です（`0`→1000、`1`–`99`→100、`100`–`60000`→そのまま、`60001`–`65535`→60000）。`hex` は生値、`normalized_interval_ms` は送信側が適用する値です。

東京駅の例:

```
lat = 35.6812360 → 356812360 = 0x15448648 → 48 86 44 15
lon = 139.7671250 → 1397671250 = 0x534EC552 → 52 C5 4E 53
packet = 01 03 2A 00 48 86 44 15 52 C5 4E 53 03 00 05 00 00 52 17 69
```

実装の詳細は [docs/protocol.md](https://github.com/haruki0420/p2pgps-ios/blob/main/docs/protocol.md) を参照してください。
