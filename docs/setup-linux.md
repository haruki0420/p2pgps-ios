# Linux / WSL で xtool を使って iOS アプリをビルドする

`p2pgps-ios` は Mac なしでビルドできるよう、[xtool](https://github.com/xtool-org/xtool) を前提にしています。このドキュメントは Ubuntu 24.04 / WSL2 を想定した手順です（Arch などでも概ね同じですが、パッケージ名が異なります）。

> xtool は Windows ネイティブでは動作しません。**WSL2 の Ubuntu** か、Linux 実機を使ってください。

## 1. 前提パッケージ

```bash
sudo apt-get update
sudo apt-get install -y \
  curl unzip git build-essential libssl-dev libxml2-dev \
  libncurses-dev usbmuxd libimobiledevice-utils \
  fuse libfuse2 pkg-config
```

- `usbmuxd` / `libimobiledevice-utils`: 実機接続と `idevice_id -l` に必要。
- `libfuse2`: xtool の AppImage 実行に必要。

## 2. Swift ツールチェーン

Swiftly（推奨）または swift.org のツールチェーンを導入します。Swift 6.0 以上が必要です。

```bash
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init -y --platform ubuntu24.04
. ~/.local/share/swiftly/env.sh
swift --version   # 6.x
```

## 3. xtool の導入

```bash
curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" \
  -o ~/.local/bin/xtool
chmod +x ~/.local/bin/xtool
xtool --help
```

## 4. iOS SDK の準備

xtool は Apple の iOS SDK を必要とします（Xcode の `.xip` から抽出）。

1. Apple Developer Downloads から Xcode の `.xip` を取得（ブラウザでダウンロード。無料 Apple ID でも取得できます）。
2. `xtool sdk install /path/to/Xcode.xip`
3. `xtool sdk list` で `darwin` 系の SDK が見えることを確認。

## 5. Apple ID の設定（サイドロード用）

```bash
xtool setup
```

- **無料の Apple ID** を推奨（Personal Team）。パスワードはキーチェーンではなく xtool の管理下に保存されます。
- 2 要素認証が有効な場合は、アプリパスワードではなく通常のパスワード + 2FA コードを求められます。

## 6. このリポジトリのビルド

```bash
git clone https://github.com/haruki0420/p2pgps-ios.git
cd p2pgps-ios

# ベンダーの静的ライブラリを取得（約 92.6 MB、SHA-256 検証つき）
bash scripts/fetch-vendor.sh

# ビルド
xtool dev build

# 実機へインストールして起動
xtool dev run
```

初回は SwiftPM が iOS SDK 向けの標準ライブラリモジュールをビルドするため数分かかります。2 回目以降はキャッシュされ高速です。

## 7. 端末側の準備

- iPhone / iPad で **Developer Mode** を有効化（設定 > プライバシーとセキュリティ > デベロッパモード）。
- USB 接続し、`idevice_id -l` で UDID が見えることを確認。
- 初回 `xtool dev run` で「信頼」ダイアログが出たら許可。
- インストール後、設定 > 一般 > VPN とデバイス管理 で開発者を信頼。

## 8. 確認コマンド

```bash
swift --version
xtool --help
xtool sdk list
idevice_id -l
```

## 9. この環境で確認できないこと

- 実機の BLE ペリフェラル / セントラル動作
- 位置注入（LocalDevVPN / pairing file / DDI が必要）
- Simulator での UI 確認（Simulator は macOS 専用）

これらは実機での確認が必要です。CI（GitHub Actions の macOS ランナー）はコンパイルとリンクのみを検証します。
