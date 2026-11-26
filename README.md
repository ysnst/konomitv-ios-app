# KonomiTV FS — サーバー無改造のiOSラッパー

[tatsuya0902/konomitv-ios-app](https://github.com/tatsuya0902/konomitv-ios-app) を基にした、WKWebViewの全画面対応版です。既存のネイティブ版KonomiTV Viewerとは独立したプロジェクトです。本家の履歴・MITライセンスを保持しています。

既存のKonomiTV全画面ボタンから、字幕・実況・操作部品を含むWebプレイヤー全体を表示し、iOSの横向き・ステータスバー非表示へ接続します。サーバーの橋渡しパッチ適用や再ビルドは不要です。動画専用のiOS標準全画面へは移しません。

現在は実機確認前の試作です。公開KonomiTV v0.14.1のFullscreen API契約を対象とし、利用中のサーバーが同じ実装かは別途確認が必要です。HEVC録画・生放送・PiPは元ラッパーでの利用者確認を基準とし、この改造版での回帰確認は未実施です。

## 導入

GitHub Actionsの`Build unsigned fullscreen IPA`が成功した実行から、`fullscreen-0.2.0-<build>-<SHA>`成果物をダウンロードします。zip内の未署名IPAをLiveContainerへ導入してください。公開リリースや固定タグへの自動アップロードは行いません。

表示名は`KonomiTV FS`、bundle IDは`jp.ysnst.konomitv.fullscreen`です。元アプリと区別するため別IDを使用します。初回は接続先URLを入力し、Cloudflare Accessへ再ログインしてください。元アプリの設定・Cookieは移行しません。元アプリの領域を消したり、データ領域を共有したりしないでください。

入力したURLは従来と同じ`konomi_url`キーに保存します。設定アプリからも変更できます。CookieはWKWebViewの永続ストアをそのまま使用します。

## 開発と検証

Swift 5 / iOS 16以降、外部Swift依存なし。ReleaseビルドはmacOS Actionsで行います。ワークフローは作業ブランチのコード変更で1回起動し、IPA・SHA-256・ビルド元完全SHA・Xcodeログを保存します。版は0.2.0、build番号はActionsのrun_numberです。

JavaScriptの契約テストは、固定SHAの公開PlayerControllerを読み込み、型注釈だけ除いた全画面ハンドラーを実ブラウザで実行します。テスト対象のソースは`artifacts/reference/PlayerController-v0.14.1.ts`へ取得し、`PLAYWRIGHT_MODULE`にPlaywrightのパスを指定して`node tests/fullscreen-browser.cjs`で実行します。CIはPlaywright WebKit、Windowsでは検証専用Chromiumを使用します。

[調査と来歴](docs/baseline.md)、[要件](docs/requirements.md)、[構成](docs/architecture.md)、[実機チェックリスト](docs/device-checklist.md)を参照してください。`work-result-v0.md`、`build-result-v1.md`、`konomitv-client-bridge.patch`は本家の過去記録・参考資料で、今回のサーバー操作手順ではありません。

## ライセンス

MIT License。元の著作権表示は[LICENSE](LICENSE)を参照してください。
