# SideStore / AltStore ソース（自動更新）

P2P GPS を **SideStore / AltStore のソース**に追加すると、新しいバージョンがリリースされたときに SideStore の一覧へ自動で表示されます。

## ソースの形式

`source/apps.json` が [AltStore のソース形式（apps.json v2）](https://faq.altstore.io/developers/make-a-source)です。SideStore も同じ形式を読みます。

- `apps[].versions[]` に IPA の URL・サイズ・SHA-256・リリース日・変更点を並べています。
- `scripts/generate_source.py` が GitHub Release から自動生成します。
- `.github/workflows/update-source.yml` が **Release IPA ワークフローの成功後**に `source/apps.json` を更新して `main` にコミットします。

## 公開 URL が必要です

SideStore はソースを **認証なしの公開 URL** から取得します。リポジトリが private のままだと `raw.githubusercontent.com` の URL にアクセスできないため、次のいずれかが必要です。

### 方法 A: `p2pgps-ios` を public にする（最も簡単）

1. リポジトリを public に変更
2. SideStore → Sources → **+** → 次を追加:

   ```
   https://raw.githubusercontent.com/haruki0420/p2pgps-ios/main/source/apps.json
   ```

3. ソースに P2P GPS が表示され、リリースごとに新バージョンが出ます。

> AGPL-3.0 のアプリを配布する場合、バイナリの受領者に対応するソースを提供する必要があります。public リポジトリはこれを満たします。

### 方法 B: 公開用の `p2pgps-source` リポジトリを作る

ソースコードを private のままにしたい場合は、公開専用の小さなリポジトリを作ります。

1. public リポジトリ `p2pgps-source` を作成
2. `source/apps.json` をそこにコピー（CI から push する場合は `SOURCE_REPO_TOKEN` を追加）
3. IPA も公開する必要があります。GitHub Release のアセットは private リポジトリだと取得できないため、`p2pgps-source` の Release に IPA をアップロードするか、GitHub Pages などに置きます
4. SideStore に `https://raw.githubusercontent.com/haruki0420/p2pgps-source/main/apps.json` を追加

> AGPL のソース提供義務を満たすため、`p2pgps-source` の Release にソース tarball を添付するか、ソースコードも公開してください。

### 方法 C: GitHub Pages

public リポジトリの GitHub Pages に `apps.json` を置き、その URL を SideStore に追加します。方法 A/B と組み合わせて使えます。

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
