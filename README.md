# P2P GPS for iOS / iPadOS

iPhone から現在地を送り、iPad の位置として使えるようにするアプリです。iPad 側は位置を書き換えるために、pairing file・LocalDevVPN・Developer Disk Image（DDI）を使います。

- **これは何**: iPhone を Sender、iPad を Receiver にして、BLE で位置を渡す iOS / iPadOS アプリ。
- **誰向け**: Mac を持たず、iPhone から iPad の位置を合わせたい技術志向の人。位置依存アプリの QA・デモ担当。
- **制約**: iOS / iPadOS 17.0 以降。送信だけなら iPhone 単体で動く。受信には iPad の Developer Mode / LocalDevVPN / pairing file / DDI が必要。
- **状態**: 検証状況はハブ Wiki の [Status](https://github.com/haruki0420/p2pgps/wiki/Status) を参照。

## 必要なもの

- iPhone / iPad: iOS / iPadOS 17.0 以降
- iPad 側: Developer Mode、LocalDevVPN、pairing file、DDI
- インストール: SideStore / AltStore（未署名 IPA）

## 使い方

1. iPad にアプリを入れる
2. iPad の設定で Developer Mode を ON、LocalDevVPN を接続
3. pairing file を読み込む
4. DDI をダウンロードして使える状態にする
5. 送信側のスマホで「送信を開始」
6. iPad 側で送信元を選び、「位置情報を反映」を ON

詳しい手順: [Setup iPad](https://github.com/haruki0420/p2pgps-ios/wiki/Setup-iPad)

## ビルド

- [Build](https://github.com/haruki0420/p2pgps-ios/wiki/Build)
- [Source / SideStore](https://github.com/haruki0420/p2pgps-ios/wiki/Source)

## ドキュメント

- [Wiki の Home](https://github.com/haruki0420/p2pgps-ios/wiki)
- [困ったとき](https://github.com/haruki0420/p2pgps-ios/wiki/Troubleshooting)
- [よくある質問](https://github.com/haruki0420/p2pgps-ios/wiki/FAQ)

## ライセンス

AGPL-3.0。位置の書き換え部分は StikDebug / TLocation（AGPL-3.0）を元にしています。詳細は [License](https://github.com/haruki0420/p2pgps-ios/wiki/License) を参照してください。
