# はじめかた（Getting Started）

## 1. インストール

1. [Releases](https://github.com/haruki0420/p2pgps-ios/releases) から未署名 IPA をダウンロードします。
2. SideStore / AltStore でインストールします。
3. iPad 側は [Setup iPad](https://github.com/haruki0420/p2pgps/wiki/Setup-iPad) の準備（Developer Mode / LocalDevVPN / pairing file / DDI）を行います。

## 2. 送信側（iPhone）

1. アプリで「送信する」を選びます。
2. 位置情報を「常に許可」にします。
3. 「送信を開始」を押します。

## 3. 受信側（iPad）

1. アプリで「受信する」を選びます。
2. 「スキャン開始」を押し、`P2PGPS-...` を選びます。
3. 「位置情報を反映」を ON にします。

## 4. ビルド（開発者向け）

```bash
git clone https://github.com/haruki0420/p2pgps-ios.git
cd p2pgps-ios
bash scripts/fetch-vendor.sh
xtool dev build
```

詳しくは [Build](Build) を見てください。

## うまくいかないとき

[困ったとき](Troubleshooting) を見てください。
