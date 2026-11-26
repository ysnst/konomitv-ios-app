# 全画面ブリッジ

既存WKWebViewを維持し、`FullscreenBridge.js`をリソースとして同梱する。接続先URLを設定・読込時に正規化し、WKUserScriptをdocument start / main frame onlyで登録する。JSは信頼origin以外で即終了し、`/tv/watch/<id>`と`/videos/watch/<id>`かつ既存watchコンテナがある場合だけAPI/CSSを変更する。

body.requestFullscreen → JSの全画面状態 → body.fullscreenchange → 公開PlayerController → player_store.is_fullscreen の経路でWebを同期し、既存konomiNative通知でネイティブを変更する。document.fullscreenElementは全画面中だけbodyを返す。videoのFullscreen/PiP/再生メソッドには触れない。is_pseudo_fullscreenを立てずCSSで90度回転しない。

ネイティブは現在URLと送信フレームURLのorigin、WebKit securityOrigin、main frame、対象WebView、type、厳密なBooleanを検証する。SPAではフレームrequestが初期URLの場合があるので、視聴pathの検証は現在WebView URLに対して行う。認証リダイレクト自体は従来どおり許可する。

全画面中はWebViewを四辺へ広げ、ステータスバーを隠しホームインジケーターの自動非表示を要求する。既存UIWindowScene回転を利用し、解除時は開始姿勢を問わず縦へ戻す。回転要求エラーは同じ世代の操作に限り状態を戻す。OS/LiveContainerが要求を拒否する可能性は実機で確認する。

MutationObserverはwatchコンテナの生成・破棄とハンドラー再生成に追随する。画質変更でvideoだけ交換されても全画面を維持する。watchコンテナ交換では解除し、再度全画面化できるよう再登録する。視聴画面離脱では元のAPI descriptorとCSSを復元する。pagehide/非表示/scene非アクティブ/新規ナビゲーションでは解除する。PiP移行時も映像を止めず、復帰後は通常表示から再度全画面を選ぶ。

保存URL・Cookieストア・音声セッション・再生処理は既存方式。bundle IDは`jp.ysnst.konomitv.fullscreen`、表示名は`KonomiTV FS`として既存版と区別する。LiveContainerのデータ領域を共用・移行しない。初回にURLとCloudflare認証を入力する。

配信はActions Artifactsのみ。公開release/tagの作成・既存資産の上書きは行わない。IPA名とメタデータに0.2.0/build番号/完全SHAを含める。
