# PiPを使わない背景音声の検証

0.3.1 / `codex/background-audio`は利用者の追加依頼に対する検証版。安定版mainの0.2.3を維持し、実機結果を受け取るまで統合しない。自動PiPは実装しない。背景音声の再開対象は録画のみ。ライブは0.3.0/build 10で失敗し、根治できていないため対象外とする。

## 方式

元からある`UIBackgroundModes=audio`と起動時のAVAudioSession設定を維持する。WebKitはインライン動画を背景で止める場合があるため、既に再生していた同じvideoへ背景入り直後に1回だけplayを要求する。新しいaudio/video、AVPlayer、配信API、音声ファイルは作らない。映像ストリームの受信も元のままで、通信量を音声のみへ削減する機能ではない。

1. NativeのsceneWillResignActiveで録画視聴ページの再生中videoを記憶する。ライブ・PiP・ミュート・エラー・一時停止済みは対象外。
2. sceneDidEnterBackgroundとdocument.hiddenが両方成立した最初の観測で確認する。録画視聴のまま同じvideo/currentSrcで、記憶から2.5秒以内かつ既知の音声割り込みがない場合だけ対象にする。記憶後にライブへ遷移した場合も対象外。
3. その時点で停止済みならplayを1回試す。既に再生中なら候補を破棄する。pauseイベントを契機に再開したり、タイマーで再試行したりしない。
4. 前景復帰・ページ離脱・動画交換では候補を破棄する。前景復帰で音声セッションを再設定しない。

Control Centerを開くだけではNativeの背景通知がないので実行しない。背景通知より前のpauseも候補を破棄する。背景入りの瞬間に生じたOS停止と手動停止をWebのpauseイベントから完全に識別することはできないため、最初のhidden判定の直前に利用者が停止した場合の扱いは実機でも確認する。背景中に継続していた再生を後から止めた場合は再開しない。

## 制限と確認状況

2026-11-27、0.3.0/build 10提供後の利用者報告では、録画の背景音声は動作し、リアルタイム視聴ではうまく動作しない。同日の診断（187件）では6回の再開要求すべてが成功した後、4回は47〜56msでerror=3になった。単なるplay拒否ではなくデコード段階の失敗が記録されている。ただしログにはライブ／録画の識別がなく、失敗したコーデック・配信経路・内部原因は確定できない。0.3.1は利用者のライブ失敗報告を踏まえてライブの強制再開だけを除外し、根治とは扱わない。

400秒台の再生群にも当初の時計固着がある一方、後半は背景3.2／6.5／12.4秒に対してほぼ同じ時間だけ再生位置が進んだ。録画の全条件を合格とは扱わず、可聴音と長時間の安定性を引き続き確認する。詳しい時系列はdiagnostics.mdを参照。

ブラウザの契約テストは通知順・除外条件・1回だけの呼び出し・手動停止の維持を確認する。動画状態を模擬しているため、実際の音声出力、iOSのWebKit、LiveContainer、長時間のライブ配信を保証しない。

WebKitがJSを停止したりplayを拒否したり、hidden判定の後に動画を止めたりした場合、この方式では継続できない。後からの自動再試行で手動停止を上書きしない方を優先する。録画とライブ、Home移行と画面ロック、全画面と通常表示を分けて実機で確認する。サーバーや配信方式の変更で回避しない。

診断には`background-audio-attempt`、`background-audio-started`、`background-audio-rejected`を追加した。startedはplay Promiseが成功したことだけを意味し、音が出続けた証明にはならない。認証情報や配信URLは記録しない。

## 調査した一次資料

- [Apple: Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback): アプリの背景音声設定。
- [WebKit: MediaSessionManagerIOS.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/MediaSessionManagerIOS.mm): iOSの背景再生制限。
- [WebKit: HTMLMediaElement.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/html/HTMLMediaElement.cpp)、[PlatformMediaSession.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/PlatformMediaSession.cpp): 動画とメディアセッションの状態遷移。
- [Brave: media_backgrounding.ts（e19caaec）](https://github.com/brave/brave-core/blob/e19caaec3fbd6c4a7cdcd449085c7d8042ac1410/ios/browser/web/media/resources/media_backgrounding.ts): 利用者の情報提供から調査。同じvideoのplayで再開する実装例がある。ただしDocument.visibilityStateをvisibleへ変更し、videoのplay/pauseを広く置き換え、PiP関連イベントの伝播も止めている。今回の方式はこのコードを取り込まず、可視状態・prototype・PiPイベントを変更しない。
- [WebKit Bug 290846](https://bugs.webkit.org/show_bug.cgi?id=290846): iOS背景移行時のMSEデコードエラーの類似報告。[当時の修正](https://github.com/WebKit/WebKit/commit/33f4fb391d87070299a7555a8397b6d444291147)は内部設定の既定値変更であり、今回と同一原因とも、公開WK APIで回避できるとも確認していない。

WebKitの公開mainは使用端末のiOS 26.7.3と同一ソースだと確認できていない。公開ソース上の可能性をもとにした検証であり、実機での成立は未確認。
