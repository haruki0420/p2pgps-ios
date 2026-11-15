# SideStore / AltStore ソース（自動更新）

P2P GPS を **SideStore / AltStore のソース**に追加すると、新しいバージョンがリリースされたときに SideStore の一覧へ自動で表示されます。

## ソースの形式

`source/apps.json` が [AltStore のソース形式（apps.json v2）](https://faq.altstore.io/developers/make-a-source)です。SideStore も同じ形式を読みます。

- `apps[].versions[]` に IPA の URL・サイズ・SHA-256・リリース日・変更点を並べています。
- `scripts/generate_source.py` が GitHub Release から自動生成します。
- `.github/workflows/update-source.yml` が **Release IPA ワークフローの成功後**に `source/apps.json` を更新して `main` にコミットします。

## SideStore への追加手順

SideStore は AltStore ソースと完全互換です（[SideStore Docs: App Sources](https://docs.sidestore.io/docs/advanced/app-sources)）。

### 方法 1: ワンクリックリンク

SideStore がインストールされた iPad で次のリンクを開きます。

```
sidestore://source?url=https%3A%2F%2Fraw.githubusercontent.com%2Fharuki0420%2Fp2pgps-ios%2Fmain%2Fsource%2Fapps.json
```

### 方法 2: 手動で追加

1. SideStore → **Sources** → **+**
2. 次を入力:

   ```
   https://raw.githubusercontent.com/haruki0420/p2pgps-ios/main/source/apps.json
   ```

3. ソースに P2P GPS が表示され、リリースごとに新バージョンが出ます。

### 注意点

- IPA は**未署名**のまま配布しています（SideStore が Apple ID で署名します）。
- `marketplaceID` / `build` フィールドは入れていません。これらがあると SideStore は「公証済みソース」と誤認して追加を拒否します。
- ソースの `appPermissions` は AltStore 形式（`entitlements` / `privacy` の dict）で記述しています。

## 公開 URL（設定済み）

`p2pgps-ios` リポジトリは public です。上記 URL をそのまま使えます。

- AGPL-3.0 のソース提供義務も public リポジトリで満たしています。

### 代替: 公開用リポジトリ / GitHub Pages

ソースコードを private に戻したい場合は、公開専用の `p2pgps-source` リポジトリを作り、`source/apps.json` と IPA をそこへミラーする方法もあります（CI から push する場合は `SOURCE_REPO_TOKEN` が必要）。GitHub Pages に `apps.json` を置く方法でも構いません。

## 更新の自動化の範囲

- **ソースの更新**: 自動（Release IPA 成功 → `update-source.yml` → `apps.json` 更新）
- **SideStore 側の検知**: 自動（ソースを再取得して新バージョンを表示）
- **アプリのインストール**: ユーザー操作が必要（SideStore で「更新」をタップ）。iOS のサイドロードではバックグラウンドでの無音自動インストールはできません。
- **7 日制限の更新**: SideStore の「7 DAYS」で更新（ソースとは別）

## 手動でソースを更新する

```bash
python3 scripts/generate_source.py --tag v1.0.4
```

`gh` CLI が認証済みである必要があります（CI では `GH_TOKEN` を渡しています）。

## 注意

- IPA は **未署名**のまま配布します（SideStore が Apple ID で署名します）。
- ソースの `size` はバイト単位、`sha256` は IPA の SHA-256 です。
- `minOSVersion` は 17.0 です。
