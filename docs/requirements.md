# 今回の要件

対象はKonomiTV Web版を表示する薄いWKWebViewラッパー。既存ネイティブViewerとは独立する。iPhone 17 Pro / LiveContainer、Cloudflare Access、HEVC録画中心の環境を対象とし、Windowsで開発、macOS GitHub Actionsで未署名Release IPAを生成する。

- サーバー・配信方式・Cloudflare・プロキシを変更しない。サーバーパッチ、再ビルド、API追加、不要な再エンコードは禁止。
- 既存全画面ボタンでプレイヤー全体を表示し、OS横向き、ステータスバー非表示、ホームインジケーター自動非表示を要求する。動画専用のiOS全画面へ移さない。
- 解除時は縦向きと通常UIに戻す。再生・位置、字幕・文字スーパー・実況・シーク・画質・操作部品を維持する。CSSの90度回転は行わない。
- 再生処理・PiP許可・音声セッション・Cookie永続化・接続URL保存の既存方式を保持する。VLCKit、独自AVPlayer、SwiftによるWeb UI再実装は導入しない。
- JS変更は信頼originの視聴ページへ限定し、ネイティブ受信もorigin/main frame/形式/値を検証する。認証情報をログに出さない。
- 本家履歴とライセンスを維持し、作業ブランチを使う。本家への送信、PR、公開release/tag作成はしない。
- 自動契約テストと実機確認を区別する。実機結果が届くまではオフライン保存など追加機能を実装しない。

ベースラインと根拠はbaseline.md、実装方式はarchitecture.md、実機受入項目はdevice-checklist.mdを参照。
