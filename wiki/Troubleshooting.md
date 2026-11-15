# 困ったとき

## まず確認すること

1. 送信側で「送信を開始」を押しているか
2. iPad の Bluetooth が ON か
3. 2 台を近く（数 m 以内）に置いているか
4. iPad で LocalDevVPN が接続済みか
5. iPad で Developer Mode が ON か

## 送信元が見つからない

- 送信側で「送信を開始」を押す。
- iPad で「スキャン開始」を押し直す。
- 送信側のアプリを画面の前に出す。
- 他の Bluetooth アプリ（StikDebug / TLocation など）を終了する。

## 接続できない / すぐ切れる

- 送信側のアプリを画面の前に出す。
- iPad の設定で「自動再接続」が ON か確認する。
- Bluetooth を OFF/ON してから再試行する。

## 位置が反映されない

1. iPad で「位置情報を反映」が ON か確認する。
2. 送信側が現在地を測位できているか確認する（屋内では時間がかかります）。
3. 設定で DDI が「準備済み」か確認する。
4. 「困ったとき」画面で「確認を実行」を押す。

## pairing file が通らない

- 設定で pairing file を読み込み直す。
- iOS 27 では、iloader の pairing file が通らないことがあります。**`idevice_pair--windows-x86_64`（Windows x86_64 版）** で作り直してください。
- 手順: [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) → Remote pairing → Create → Validate → Save to file → アプリで読み込み直す。

## 詳しい情報（開発者向け）

- 接続の確認は「困ったとき」画面の「確認を実行」で行えます。
- 技術的なエラーは同じ画面の「動作記録」に残ります。
- ビルドで `libidevice_ffi.a` が無い場合は `./scripts/fetch-vendor.sh` を実行します（Windows は `scripts/fetch-vendor.ps1`）。

## 既知の制約

- Bluetooth での位置の受け渡しと、iPad の位置の書き換えは Android 実機 + iPad で確認済みです。全画面 UI・Dynamic Type・Dark Mode は未確認です。
- iPad の位置変更は Apple の非公開機能に依存するため、OS の更新で動かなくなる可能性があります。
- Bluetooth は 1 対 1 接続です。
