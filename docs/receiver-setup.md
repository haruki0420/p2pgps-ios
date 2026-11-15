# iPad（Receiver）セットアップ手順

iPad 側で位置情報を「別の場所」に固定するには、**SideStore / iloader** でアプリをサイドロードし、**pairing file** と **Developer Disk Image（DDI）**、端末自身へ接続するためのループバック VPN を用意する必要があります。

このプロジェクトでは、次の流れを前提とします。

```
iloader で SideStore をインストール
  → iloader で pairing file を注入 / エクスポート
  → SideStore で p2pgps-ios（未署名 IPA）をインストール
  → 本アプリに pairing file をインポート
  → LocalDevVPN 接続 → DDI ダウンロード → 位置注入
```

**Mac は不要**です。初回セットアップには Windows / macOS / Linux のコンピュータと USB ケーブルを使います（ビルドも xtool で Mac 不要）。

> このアプリの位置注入は StikDebug / TLocation と同じ仕組み（idevice FFI + RSD トンネル）を使います。手順の背景は [StikDebug-Guide](https://github.com/StikDebug/StikDebug-Guide) も参考になります。

## 0. 前提

| 項目 | 内容 |
| :--- | :--- |
| 端末 | iPad（iPadOS 17 以降） |
| コンピュータ | Windows / macOS / Linux（初回セットアップのみ。USB 接続） |
| セットアップツール | [iloader](https://iloader.app)（無料・オープンソース。[nab138/iloader](https://github.com/nab138/iloader)） |
| Apple ID | 無料アカウントで可（SideStore の署名に使用） |
| 必須アプリ | [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)（無料） |
| 必須ファイル | pairing file（`.mobiledevicepairing` / `.mobiledevicepair` / `.plist`） |
| ネットワーク | Wi-Fi（インターネット不要。テザリングでも可） |

## 1. iloader で SideStore をインストール

1. コンピュータに **usbmuxd** を用意します（Windows: iTunes / macOS: 標準搭載 / Linux: パッケージマネージャ）。
2. [iloader.app](https://iloader.app) または [GitHub Releases](https://github.com/nab138/iloader/releases) から iloader をインストールします。
3. iPad を USB ケーブルで接続し、iPad 側で「このコンピュータを信頼」→ パスコードを入力します。
4. iloader を開き、**Apple ID でサインイン**します（大文字・小文字に注意）。
5. デバイスを選択し、**「Install SideStore (Stable)」** を実行します。
6. iPad 側で開発元を信頼します: 設定 > 一般 > **VPN とデバイス管理** > 「デベロッパ App」> Apple ID を選択 > **信頼** > パスコード。
7. **Developer Mode** を ON にします: 設定 > プライバシーとセキュリティ > **デベロッパモード** > ON → 再起動 → ロック解除後に確認。
8. App Store から **LocalDevVPN** をインストールし、開いて **Connect** します。
9. **SideStore** を開き、iloader と同じ Apple ID でサインインします。
10. 「My Apps」で SideStore の **「7 DAYS」** をタップして更新し、セットアップを完了します。

> 無料の Apple ID では、SideStore とインストールしたアプリは **7 日で期限切れ**になります。SideStore の「7 DAYS」をタップして更新するか、iloader から再インストールしてください。

## 2. pairing file を用意する（iloader から注入 / エクスポート）

iloader は SideStore 用の **RPPairing / lockdown pairing file** を自動で配置します。本アプリでも同じ pairing file を使うため、**iloader からエクスポート**して iPad の Files に置きます。

1. iloader でデバイスを選択します。
2. **「Manage Pairing File」** を開き、SideStore（必要なら StikDebug など）の右側の **「Place」** を押して pairing file を配置します（「Pairing file placed successfully!」と表示されれば OK）。
3. エクスポート機能で pairing file をコンピュータに保存します（ファイル名は `pairingFile.mobiledevicepairing` など）。
4. AirDrop / iCloud Drive / Files などで **iPad の Files アプリ**に転送します。

- すでに StikDebug / TLocation を使っている場合は、そのアプリの pairing file をエクスポートして使うこともできます（**必ず同じ iPad の pairing file** を使ってください）。
- **期限切れ・ランダムに無効化された場合**: iloader で「Delete Stored Pairing」→ デバイスで Trust →「Manage Pairing File」→「Place」→ 再度エクスポート → 本アプリで再インポート、の順で復旧します。

> **iloader の対応状況**: iloader v2.4.1 の「ペアリングファイルの管理」には、まだ **P2P GPS が一覧に表示されません**（対応アプリの一覧が固定のため）。**「エクスポート（非推奨）」で pairing file を保存 → AirDrop / Files で iPad に置く → 本アプリでインポート**、の手順を使ってください。本アプリは Documents に置かれた pairing file も自動で読み込みます。

> pairing file は秘密情報です。他人に共有したり、リポジトリにコミットしたりしないでください。本アプリは Application Support の `Pairing/` 配下に 0600・Data Protection（`completeUntilFirstUserAuthentication`）・バックアップ除外で保存し、Documents に残ったコピーは読み込み後に削除します。ログには出しません。

## 3. 本アプリ（p2pgps-ios）をインストール

1. [Releases](https://github.com/haruki0420/p2pgps-ios/releases) から未署名 IPA（`p2pgps-ios-<tag>-unsigned.ipa`）をダウンロードします。
2. **SideStore** に IPA を渡してインストールします（SideStore が Apple ID で署名します）。
   - または iloader の「Import any IPA」で直接インストールすることもできます。
3. 初回起動時に「信頼されていない開発元」と表示された場合は、設定 > 一般 > VPN とデバイス管理 で開発元を信頼します。

## 4. 本アプリに pairing file を読み込む

1. P2P GPS を起動し「設定」を開きます。
2. **「pairing file を読み込む」** → Files から手順 2 で保存したファイルを選択します（`.mobiledevicepairing` / `.mobiledevicepair` / `.plist` に対応）。
3. 「読み込み済み」と表示されれば OK です。トンネルの再試行が自動で走ります。
4. 初回のトンネル接続時に **「ローカルネットワーク」の許可** を求められます。これは Remote Pairing サービスを Bonjour（`_remotepairing._tcp`）で検出するために必要です。**許可**してください（拒否した場合は 設定 > プライバシーとセキュリティ > ローカルネットワーク で P2P GPS を ON にしてください）。

> iloader が今後「配置」に対応すると、Documents に置かれた pairing file は **アプリ起動時・フォアグラウンド復帰時・設定を開いたときに自動で読み込まれます**。手動で再読み込みしたい場合は、設定の「Documents から再読み込み」を押してください。

## 5. LocalDevVPN を接続

1. **LocalDevVPN** を開いて **Connect** します（ステータスバーに VPN アイコンが表示されます）。
2. LocalDevVPN は iPad 自身を `10.7.0.1` として公開します。本アプリの Settings の**ターゲット IP が `10.7.0.1`**（既定値）であることを確認してください。
3. **Wi-Fi に接続している必要があります**（RSD / lockdownd は Wi-Fi 関連時のみ開放されます）。
4. Remote Pairing のポートは固定値ではなく、Bonjour で自動検出します（検出できない場合は 49152 にフォールバック）。診断画面の「Remote Pairing ポート」で検出結果を確認できます。

> LocalDevVPN が使えない場合（他の VPN と競合する、Tailscale を常時使いたい等）は、Tailscale + リフレクターなどの代替手段があります。仕組みと手順は [ネットワーク構成（LocalDevVPN の仕組みと代替手段）](https://github.com/haruki0420/p2pgps/blob/main/docs/networking.md) を参照してください。

## 6. DDI をダウンロードしてマウント

1. 設定の「DDI をダウンロード」を押す（Image.dmg / Image.dmg.trustcache / BuildManifest.plist を取得）。
2. 完了後、自動でマウントを試みます。失敗する場合は「DDI をマウント」を押す。
3. 「マウント済み」になれば準備完了。

DDI の取得元: [doronz88/DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage)（PersonalizedImages/Xcode_iOS_DDI_Personalized）。URL は固定コミット `a1020f81b6429f5ce40408cbe21c690512b613b5` に固定し、ダウンロード後に 3 ファイルすべての SHA-256 を検証します。不一致のファイルは削除してエラーを表示するので、その場合は再取得してください。

## 7. 位置を反映する

1. iPhone 側で P2P GPS を開き「送信する」→「送信を開始」。
2. iPad 側で「受信する」→「スキャン開始」。
3. 一覧に `P2PGPS-IOS-XXXX` が現れたら選択。
4. 座標が表示されたら「位置情報を反映」を ON。
5. 上部にライブバナー（送信元・座標・停止）が表示され、iPad の位置が送信側の位置に固定されます。

## 8. うまくいかないとき

| 症状 | 確認すること |
| :--- | :--- |
| 送信元が見つからない | iPhone 側で「送信を開始」しているか。Bluetooth が ON か。近距離か。 |
| トンネル接続に失敗する | **診断画面 →「接続診断を実行」** で pairing file の形式・Wi-Fi・Remote Pairing ポートへの TCP 到達性を確認。あわせて LocalDevVPN が接続中か、他の VPN が有効でないか、Developer Mode が ON か、ターゲット IP が `10.7.0.1` かを確認。 |
| 診断で「ローカルネットワーク」の許可が必要と出る / ポート検出が Fallback になる | 設定 > プライバシーとセキュリティ > ローカルネットワーク で P2P GPS を ON にしてから、アプリを再起動して再試行。 |
| 診断で pairing file が「lockdown のみ」と出る | iloader でエクスポートし直し（RPPairing を含むファイル）、本アプリで再インポート。 |
| 診断で TCP が「接続待ち / 失敗」と出る | LocalDevVPN を接続し直す。Wi-Fi を OFF/ON。他の VPN を切断。ローカルネットワークの許可を確認。 |
| pairing file が無効と言われる | iloader で pairing file を再配置・再エクスポートしてインポートし直す。期限切れの可能性。 |
| iOS 27 で `ConnectionReset`（code 54）になる | 下記「iOS 27 以降で ConnectionReset になる場合」を参照。**idevice_pair** で RPPairing を作り直してください。 |
| SideStore でアプリが起動しない / 期限切れ | SideStore の「7 DAYS」をタップして更新。改善しなければ iloader から再インストール。 |
| 「信頼されていない開発元」と表示される | 設定 > 一般 > VPN とデバイス管理 で開発元を信頼。 |
| DDI がマウントできない | DDI を再取得してから再試行。LocalDevVPN の接続を確認。 |
| 注入は成功するが位置が戻る | 送信側のアプリがバックグラウンドで停止していないか。位置情報の「常に許可」を確認。受信側は設定の「バックグラウンド維持（受信側）」が ON か確認。 |
| アプリ再起動後に位置が元に戻らない | 前回のプロセスが残したデバイス側セッションはアプリからは消せません。iPad を再起動するか、注入を ON → OFF してから再試行してください。 |

## 9. iOS 27 以降で「ConnectionReset」になる場合

iOS 27 では、iloader がエクスポートする pairing file（lockdown + RPPairing の結合ファイル）が RSD ハンドシェイクで拒否されることがあります（`ConnectionReset` / code 54）。StikDebug でも同じ報告があり、**idevice_pair で RPPairing を作り直す**ことで解決しています。

1. [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) を起動します（Windows は iTunes / usbmuxd が必要）。
   - USB 接続、または iOS 27 以降なら「Pair over Wi-Fi」も使えます。
2. デバイスを選択 → **Remote pairing** → **Create** → **Validate** で有効性を確認します。
3. **Save to file…** で `pairingFile.plist` を保存します。
4. 本アプリの Settings → **pairing file を削除** → **pairing file を読み込む** で新しいファイルをインポートします。
5. 改善しない場合は、アプリを**完全に削除** → iPad を再起動 → 再インストール → 新しい pairing file をインポートしてください（StikDebug の iOS 27 報告と同じ対処です）。

> iloader の「Delete Stored Pairing」→ Trust → Place → 再エクスポートでも改善する場合があります。まずは idevice_pair を試してください。

詳しくは [wiki/Troubleshooting.md](../wiki/Troubleshooting.md) を参照してください。
