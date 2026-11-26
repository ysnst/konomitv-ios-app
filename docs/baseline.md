# ベースライン調査（2026-11-27）

## 対象と来歴

- 本家: https://github.com/tatsuya0902/konomitv-ios-app
- 本家 main / ローカル開始SHA: `ba809b4451095e8c53efc1b8c1dce820c0587eb9`（リモート照会でも一致）。履歴・MIT LICENSEを維持。
- 独立した作業先: `C:\Users\W.ETERNAL\source\konomitv-ios-app`、origin は利用者所有 `ysnst/konomitv-ios-app`。既存ネイティブViewerは対象外。
- 本家表示版0.1、build 1。過去記録ではIPAビルド元 `771006ef0a04e00c5492431be6ea6c8cb81d8e17`（次の基準コミットは記録文書のみの変更）。利用者が導入したIPAそのものは未提供で、同一性は未確認。
- 公開リリース `sideload-latest` の `KonomiTV-iOS-unsigned-0.1.ipa` は157,416 bytes、GitHub APIのdigestは `fcc300d35614ce54beb91a7b382bea4aaf08bd247feb9be94a122b30a140bb44`。固定タグ/説明だけでは導入済みIPAのビルド元を証明できない。
- 参考クライアント: KonomiTV v0.14.1、SHA `0a32188274b81c1e7bed642474b208bd2a543a6b`。現行masterも全画面ハンドラーの同一経路を確認。導入先サーバーの版・クライアント差分は未確認。

## 本家ラッパーの構成

Swift 5 / iOS 16以降のUIKitプロジェクト。Swiftファイル3本、共有scheme `KonomiTV-iOS`、Debug/Release。外部Swift依存やPackage.resolvedはなく、UIKit/WebKit/AVFoundationを利用。WindowsにはXcode/iOS SDKがないためSwiftコンパイルはmacOS Actionsで行う。

`ViewController`がWKWebViewを1個保持。inline再生、PiP、自動再生を許可し、UAへ `KonomiTV-iOS/0.1` を追記する。`WKUserContentController` の `konomiNative` は既存だが、WKUserScriptは未登録。Webから `{type:'fullscreen', enter:boolean}` が来れば、ステータスバー・ホームインジケーター、制約、inset、UIWindowSceneのgeometryを変更する。元コードの受信制限は名前/辞書/typeのみで、送信元制限はなかった。

`AppDelegate`の `.playback / .moviePlayback` 音声セッションとInfo.plistのbackground audioがPiPを支える。`SceneDelegate`はwindowを作成し復帰時に音声を再有効化する。再生/配信はWeb側に任せる。

接続URLは標準UserDefaultsの`konomi_url`。設定bundleと入力画面で共用。WKWebViewの永続データストアが既定のままで、Cookie消去・独自認証実装・共有コンテナ依存はない。LiveContainer用のCFBundleExecutableも既に存在する。今回もこれらを保持し、別アプリIDで既存アプリの領域を上書きしない（新規アプリにはURL・認証の再入力が必要）。

## 全画面非対応の原因

[固定版PlayerController.ts](https://github.com/tsukumijima/KonomiTV/blob/0a32188274b81c1e7bed642474b208bd2a543a6b/client/src/services/player/PlayerController.ts) の `setupFullscreenHandler` は、DPlayerのrequest/cancel/isFullScreenを上書きする。

1. requestはdocument.bodyのrequestFullscreenまたはwebkitRequestFullscreenを呼ぶ。
2. 両方ない場合、`iPhone Safari は動画のフルスクリーン表示に対応していません。` をnoticeへ渡す。動画専用のwebkitEnterFullscreenへは切り替えない。
3. isFullScreenはdocument.fullscreenElement / webkitFullscreenElementを確認する。
4. bodyのfullscreenchange（またはwebkit版）でplayer_store.is_fullscreenを更新する。

このためSafariと元ラッパーで同じメッセージになる現象は、公開実装のAPI不在経路と一致する。公開v0.14.1にはis_pseudo_fullscreenはない。参考customizationsは独自の擬似全画面を追加しており、元ラッパー同梱パッチはその改造ツリー用の案である。公開の完成版`ios-app-bridge.patch`は破棄時の終了通知/PiP終了補完も追加している。パッチをサーバーに適用していない。

[Watch.vue](https://github.com/tsukumijima/KonomiTV/blob/0a32188274b81c1e7bed642474b208bd2a543a6b/client/src/components/Watch/Watch.vue) はis_fullscreenでクラスを切り替える。ヘッダーは操作表示中に再表示され、パネルも別フラグで残るため、既存状態通知だけでは今回の表示要件を満たさない。元のsafe-area下borderも含め、全画面中だけ限定CSSで補正する。

UAを置換せず既存印を保持する。公開Fullscreen判定自体はUAに依存しない。参考パッチはUA印でネイティブ経路へ分岐する。擬似全画面やパッチ済み独自クライアントの全派生版に互換性を保証するものではない。

## 実サーバーとの差分を読む方法

URL・認証情報は収集していない。実環境の同一性は次の読み取りだけで確認できる。

- Webの設定に表示される版と、認証済みブラウザのNetworkで`/api/version`の応答を確認（既存GETのみ）。
- NetworkのDocumentと読み込まれたassetsのファイル名・SHA-256を記録。CloudflareのログインHTMLをクライアントと取り違えない。Cookie/Authorization付きHARは共有しない。
- ブラウザ開発ツールで、`document.body.requestFullscreen`、webkit版、上記非対応メッセージを含む配信JSを検索。可能ならsource mapのsetupFullscreenHandlerを公開SHAと比較。iOSアプリの注入後のAPI値はサーバー元実装の証拠にしない。
- サーバー管理者が任意で行うなら、既存checkoutの`git rev-parse HEAD` / `git status --short`、配信済み静的ファイルのハッシュを読み取る。パッチ適用・ビルド・コンテナ操作は不要。
- HEVC無変換は利用者の再生確認として記録し、実配信経路はNetworkの既存リクエストで別途確認。アプリから配信指定は変更しない。

## 方式選定

公開実装のbody APIと状態イベントをアプリ内だけで補い、既存ボタン/Pinia/ネイティブ回転を再利用する。DPlayerの非公開インスタンス探索、Vue内部参照、クリック横取り、動画要素の移動、サーバーパッチは不要。固定公開ハンドラーをそのままブラウザで実行して成立を検証する。将来クライアントがこの契約を変更した場合は再調査する。
