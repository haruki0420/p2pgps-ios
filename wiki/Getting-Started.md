# はじめかた（Getting Started）

## 必要なもの

- iPhone（Sender）と iPad（Receiver）。iPadOS / iOS 17 以降。
- ビルド環境: **Linux / WSL2 + xtool**（Mac 不要）。または macOS + Xcode。
- iPad 側の位置注入を使う場合: **LocalDevVPN**（無料）、**pairing file**、**Developer Mode**。

## 1. リポジトリを取得

```bash
git clone https://github.com/haruki0420/p2pgps-ios.git
cd p2pgps-ios
```

## 2. ベンダーライブラリを取得

`libidevice_ffi.a`（約 92.6 MB）はリポジトリに含まれません。SHA-256 を検証しながら取得します。

```bash
bash scripts/fetch-vendor.sh          # macOS / Linux / WSL
pwsh -File scripts/fetch-vendor.ps1   # Windows PowerShell
```

## 3. ビルド（Linux / WSL + xtool）

```bash
xtool dev build     # ビルド
xtool dev run       # 実機へインストール・起動
```

xtool のセットアップ（Swift / iOS SDK / Apple ID）は [docs/setup-linux.md](https://github.com/haruki0420/p2pgps-ios/blob/main/docs/setup-linux.md) を参照してください。

### macOS + Xcode の場合

```bash
xcodegen generate
open P2PGPS.xcodeproj
```

## 4. テスト

```bash
swift test
```

プロトコル（仕様 §10 のテストベクタ）と Core（フィルタ・設定・ログ）のテストが走ります。macOS / Linux の Swift ツールチェーンで実行できます。

## 5. iPhone（Sender）の使い方

1. P2P GPS を起動し「送信する」を選ぶ。
2. 位置情報を「常に許可」にする（バックグラウンド継続のため）。
3. 「送信を開始」を押す。アドバタイズが始まります。
4. 画面を消しても送信は継続します。

## 6. iPad（Receiver）のセットアップ

初回セットアップは **Windows / macOS / Linux のコンピュータ + iloader** で SideStore を入れ、pairing file を注入する流れです（Mac は不要）。

1. **iloader** で SideStore をインストール（[iloader.app](https://iloader.app)）→ 開発元を信頼 → **Developer Mode** を ON。
2. **LocalDevVPN**: App Store からインストールし、接続。iPad 自身が `10.7.0.1` として公開されます。
3. **pairing file**: iloader の「Manage Pairing File」で Place → エクスポートし、iPad の Files に置いてアプリの「設定」→「pairing file を読み込む」。
4. **DDI**: 「設定」→「DDI をダウンロード」→ 自動でマウント。

> 無料の Apple ID では SideStore / アプリは 7 日で期限切れになります。SideStore の「7 DAYS」をタップして更新してください。

詳しい手順: [docs/receiver-setup.md](https://github.com/haruki0420/p2pgps-ios/blob/main/docs/receiver-setup.md)

## 7. 位置を反映する

1. iPad で「受信する」→「スキャン開始」。
2. 一覧から `P2PGPS-IOS-XXXX` を選ぶ。
3. 座標が表示されたら「位置情報を反映」を ON。
4. 上部のライブバナーで送信元・座標・停止ボタンを確認できます。

## 8. うまくいかないとき

[Troubleshooting](Troubleshooting) と [FAQ](FAQ) を参照してください。
