# iPad（Receiver）セットアップ手順

iPad 側で位置情報を「別の場所」に固定するには、Apple の Developer Disk Image と、端末自身へ接続するためのループバック VPN、pairing file が必要です。Mac は不要です。

> このアプリの位置注入は StikDebug / TLocation と同じ仕組み（idevice FFI + RSD トンネル）を使います。手順の背景は [StikDebug-Guide](https://github.com/StikDebug/StikDebug-Guide) も参考になります。

## 0. 前提

| 項目 | 内容 |
| :--- | :--- |
| 端末 | iPad（iPadOS 17 以降） |
| インストール方法 | SideStore / AltStore 等でサイドロード |
| 必須アプリ | [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)（無料） |
| 必須ファイル | pairing file（`.mobiledevicepairing`） |
| ネットワーク | Wi-Fi（インターネット不要。テザリングでも可） |

## 1. Developer Mode を有効化

1. iPad を Mac / PC に USB 接続して一度認識させる（サイドロード時点で認識されていれば OK）。
2. 設定 > プライバシーとセキュリティ > **デベロッパモード** を ON。
3. 再起動を求められたら再起動し、ロック解除後に「デベロッパモードをオンにする」を確認。

## 2. LocalDevVPN をインストールして接続

1. App Store で **LocalDevVPN** をインストール。
2. アプリを開いて VPN プロファイルを追加し、**接続**。
3. 接続中はステータスバーに VPN アイコンが表示されます。
4. LocalDevVPN は iPad 自身を `10.7.0.1` として公開します。アプリの設定のターゲット IP が `10.7.0.1` であることを確認してください。

## 3. pairing file を用意する

pairing file は、この iPad 自身のペアリングレコードです。取得方法はいくつかあります。

- **StikDebug / SideStore の手順で取得**: [StikDebug-Guide の pairing file ガイド](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) の手順で `pairingFile.mobiledevicepairing` を生成し、Files アプリに保存します。
- すでに StikDebug / TLocation を使っている場合は、そのアプリで使っている pairing file をそのまま利用できます。

> pairing file は秘密情報です。他人に共有したり、リポジトリにコミットしたりしないでください。本アプリは Application Support 配下に 0600 で保存し、ログには出しません。

## 4. アプリに pairing file を読み込む

1. P2P GPS を起動し「設定」を開く。
2. 「pairing file を読み込む」→ Files から `.mobiledevicepairing` を選択。
3. 「読み込み済み」と表示されれば OK。トンネルの再試行が自動で走ります。

## 5. DDI をダウンロードしてマウント

1. 設定の「DDI をダウンロード」を押す（Image.dmg / Image.dmg.trustcache / BuildManifest.plist を取得）。
2. 完了後、自動でマウントを試みます。失敗する場合は「DDI をマウント」を押す。
3. 「マウント済み」になれば準備完了。

DDI の取得元: [doronz88/DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage)（PersonalizedImages/Xcode_iOS_DDI_Personalized）。

## 6. 位置を反映する

1. iPhone 側で P2P GPS を開き「送信する」→「送信を開始」。
2. iPad 側で「受信する」→「スキャン開始」。
3. 一覧に `P2PGPS-IOS-XXXX` が現れたら選択。
4. 座標が表示されたら「位置情報を反映」を ON。
5. 上部にライブバナー（送信元・座標・停止）が表示され、iPad の位置が送信側の位置に固定されます。

## 7. うまくいかないとき

| 症状 | 確認すること |
| :--- | :--- |
| 送信元が見つからない | iPhone 側で「送信を開始」しているか。Bluetooth が ON か。近距離か。 |
| トンネル接続に失敗する | LocalDevVPN が接続中か。Wi-Fi に接続しているか。ターゲット IP が `10.7.0.1` か。 |
| pairing file が無効と言われる | pairing file を取得し直す。期限切れの可能性。 |
| DDI がマウントできない | DDI を再取得してから再試行。LocalDevVPN の接続を確認。 |
| 注入は成功するが位置が戻る | 送信側のアプリがバックグラウンドで停止していないか。位置情報の「常に許可」を確認。 |

詳しくは [wiki/Troubleshooting.md](../wiki/Troubleshooting.md) を参照してください。
