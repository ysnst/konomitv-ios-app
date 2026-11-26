# KonomiTV FS — サーバー無改造のiOSラッパー

[tatsuya0902/konomitv-ios-app](https://github.com/tatsuya0902/konomitv-ios-app) のフォークです。KonomiTVのWeb版をそのまま表示する薄いWKWebViewラッパーを維持し、**サーバーを改造せずに、字幕・実況・操作部品を含むプレイヤー全体をiOSで全画面表示する**ための変更を加えています。既存のネイティブ版KonomiTV Viewerとは独立したプロジェクトです。

## このフォークで変更したこと

| 変更箇所 | 内容 |
|---|---|
| サーバー無改造の全画面 | 本家でサーバー側の橋渡しパッチが担っていた全画面通知を、アプリ内のJavaScript注入で補います。既存のKonomiTV全画面ボタンと、本家のネイティブ回転処理を再利用します。 |
| 全画面の表示・操作 | OSを横向きにし、WebViewを画面端まで広げ、ステータスバーを隠してホームインジケーターの自動非表示を要求します。ヘッダー・ナビ・下端の余白を除去し、右側の情報パネルは既存ボタンで開閉できます。解除時は縦向きへ戻します。 |
| 背景・PiPからの復帰 | 実機ログで復帰時の音声再設定中～直後に停止が繰り返されたため、音声セッションの設定を起動時だけに限定しました。PiPや背景への移行中に全画面解除・回転を割り込ませません。 |
| 注入とメッセージの制限 | JavaScriptの変更対象を接続先の信頼されたオリジンの視聴ページへ限定。ネイティブ側でも送信元・メインフレーム・メッセージの形式と値を検証します。 |
| アプリの識別 | 表示名を`KonomiTV FS`、bundle IDを`jp.ysnst.konomitv.fullscreen`に変更し、元アプリと区別します。 |
| ビルド・検証 | GitHub ActionsでWebKitの契約テスト、Swiftの診断テスト、未署名Releaseビルドを実行します。IPA・ハッシュ・ビルド情報・ログをActions成果物に保存し、固定タグの公開リリースを自動更新する処理は外しました。 |
| 実機診断 | 音声割り込み・画面状態・動画イベントを直近300件まで記録し、3本指の長押しで診断JSONを保存できます。URL・Cookie・番組名は記録せず、自動送信もしません。 |

動画の再生基盤・配信方式はWeb版のままです。独自AVPlayerやVLCKitは導入していません。接続先URLの保存、永続Cookie、インライン再生、手動PiPの既存方式を引き継ぎ、サーバー、Cloudflare Access、リバースプロキシの設定は変更しません。

本家の履歴とMITライセンス・著作権表示を保持しています。基準コミットと調査内容は[ベースライン](docs/baseline.md)、実装の構成は[アーキテクチャ](docs/architecture.md)を参照してください。

## 現在の動作確認

`codex/background-audio`では、PiPを使わず背景へ移ったときの音声継続を試す0.3.0検証版を開発しています。安定版mainは0.2.3のままです。背景移行直後の停止に限って同じ動画の再生を1回試し、後続の一時停止を監視して再開する処理は入れていません。iOSでの音声継続は未確認です。[方式と制限](docs/background-audio.md)を参照してください。

対象はiPhone 17 Pro / LiveContainerで、HEVC録画を中心に利用する環境です。0.2.3/build 8提供後、利用者から「現状は理想どおりの動作」との確認を受けました（2026-11-27）。自動PiPは不要との決定により対応対象から外し、手動PiPを維持します。

自動テストは公開KonomiTV v0.14.1のFullscreen API契約を基準としています。利用中のサーバーと公開実装の同一性や個別項目の確認状況は[実機チェックリスト](docs/device-checklist.md)、停止の調査経緯と診断JSONの保存方法は[診断記録](docs/diagnostics.md)を参照してください。

## 導入

[GitHub Actions](https://github.com/ysnst/konomitv-ios-app/actions/workflows/build.yml)の`Build unsigned fullscreen IPA`で、mainのビルドが成功した実行を開き、`fullscreen-0.2.3-<build>-<SHA>`成果物をダウンロードします。zip内の未署名IPAをLiveContainerへ導入してください。

表示名は`KonomiTV FS`、bundle IDは`jp.ysnst.konomitv.fullscreen`です。元アプリと区別するため別IDを使用します。初回は接続先URLを入力し、Cloudflare Accessへ再ログインしてください。元アプリの設定・Cookieは移行しません。元アプリの領域を消したり、データ領域を共有したりしないでください。

入力したURLは従来と同じ`konomi_url`キーに保存します。設定アプリからも変更できます。CookieはWKWebViewの永続ストアをそのまま使用します。

## 開発と検証

Swift 5 / iOS 16以降、外部Swift依存なし。ReleaseビルドはmacOS Actionsで行います。mainへのアプリ本体・テスト・ワークフローの変更でビルドし、READMEやdocsだけの変更では起動しません。手動実行も可能です。IPA名とビルド情報には版番号・build番号・完全なコミットSHAを含めます。現在の版は0.2.3、build番号はActionsのrun_numberです。

背景音声の検証版は`codex/background-audio`を指定してActionsを手動実行し、`fullscreen-0.3.0-<build>-<SHA>`成果物を使用します。同じbundle IDを使うため、既存のKonomiTV FSを更新する場合は安定版IPAも手元へ残してください。

JavaScriptの契約テストは、固定SHAの公開PlayerControllerを読み込み、型注釈だけ除いた全画面ハンドラーを実ブラウザで実行します。テスト対象のソースは`artifacts/reference/PlayerController-v0.14.1.ts`へ取得し、`PLAYWRIGHT_MODULE`にPlaywrightのパスを指定して`node tests/fullscreen-browser.cjs`で実行します。CIはPlaywright WebKit、Windowsでは検証専用Chromiumを使用します。

[調査と来歴](docs/baseline.md)、[要件](docs/requirements.md)、[構成](docs/architecture.md)、[実機チェックリスト](docs/device-checklist.md)を参照してください。`work-result-v0.md`、`build-result-v1.md`、`konomitv-client-bridge.patch`は本家の過去記録・参考資料で、今回のサーバー操作手順ではありません。

## ライセンス

MIT License。元の著作権表示は[LICENSE](LICENSE)を参照してください。
