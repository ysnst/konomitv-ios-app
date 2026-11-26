# 再生停止の実機診断（0.2.2）

0.2.1/build 5でも、iOSコントロールセンターの開閉とアプリ背景→復帰で録画・ライブとも停止するという報告を受けた。PiPの単独切替だけでは停止せず、背景から戻る操作に伴う。ライブは停止後プレイヤー再起動まで不安定。LiveContainer 3.8.14、iOSの自動PiP設定はON。iOSの版は診断JSONへ自動記録する。

0.2.2は原因調査用であり、修正済みを示す版ではない。音声セッション再設定・再生・PiP・配信・画面回転の処理は0.2.1から変更しない。

## 記録の取り方

1. 前回のKonomiTV FSと同じLiveContainerアプリとして更新し、起動する。
2. 録画またはライブを再生し、コントロールセンターを開く→閉じる。不具合が起きた後、プレイヤーを再起動する前に記録を保存する。
3. アプリ画面を**3本指で1.5秒長押し**するとiOS標準の共有シートが開く。「ファイルに保存」で`KonomiTV-Diagnostics-….json`を保存する。
4. 背景→復帰も別に再現し、同じ方法で保存する。再生種別、通常表示/全画面、PiPの有無、操作順も記録する。

共有は利用者が選んだ保存先へだけ行う。自動送信しない。共有前の記録はメモリ上の直近300件で、アプリ終了で消える。共有シート用の一時JSONはシート終了時に削除する。保存済みファイルは利用者の保存先に残る。

3本指操作と共有シートの実機動作は確認待ち。記録の保存ができない場合はその状況を報告する。診断操作自体が画面を一時的に覆うため、問題の再現後に行う。

## 記録するもの

- アプリ版/build、iOS版、イベントの受信時刻。
- sceneのactive/inactive/background/foreground、音声セッション設定の開始/終了、割り込みtype/options/reason、経路変更reason、media services reset、Webプロセス終了。
- Web動画のplay/playing/pause/waiting/stalled/ratechange/error、PiP・visibilityイベント。現在位置、再生速度、paused/ended、readyState/networkState、現在位置からのバッファ残秒、エラー番号、PiPモード、対応環境のaudioSession state/type。

URL、Cookie、認証ヘッダー、番組名、動画ソースURL、エラー本文、音声出力先のデバイス名は記録しない。JavaScriptから受け取る形式・キー・数値範囲・列挙値を検証する。診断受付にも既存の信頼origin/main frame/視聴URL制限を適用する。

イベントは観測だけで、play/pause、動画ソースや位置・再生速度の変更、PiP要求、再起動を行わない。ユーザーが停止した再生を勝手に再開しない。

## 現在の見立てと限界

本家由来の`sceneDidBecomeActive`は復帰のたびに音声セッションをsetCategory/setActiveする。これが停止に先行するか、OSの割り込みやWeb側のpause・bufferingに先行されるかを記録で調べる。同値設定の再実行が原因とは断定していない。ライブでは公開PlayerControllerのバッファ待ちが再生速度0を使う場合があるが、導入サーバーで同じ経路かは未確認。

WKWebViewの`allowsPictureInPictureMediaPlayback`はPiPの許可で、自動inline PiPを必ず開始する設定ではない。AVKitの`canStartPictureInPictureAutomaticallyFromInline`相当の公開WK設定は確認できていない。今回のWebView全体の全画面化は、動画だけをAVKitの全画面へ移すものではない。Control Centerでも呼ばれるinactive通知にPiP要求を追加しない。

根拠:

- [Apple: 音声セッションの設定](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioSessionBasics/AudioSessionBasics.html)
- [Apple: 音声割り込み](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html)
- [WebKit: 公開WKWebViewConfiguration](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewConfiguration.h)
- [Apple: PiPと自動開始](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player)

実機記録を確認するまで、停止原因・自動PiPが実現できる範囲を確定しない。
