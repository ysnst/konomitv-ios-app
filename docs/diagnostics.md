# 再生停止の実機診断

0.2.1/build 5でも、iOSコントロールセンターの開閉とアプリ背景→復帰で録画・ライブとも停止するという報告を受けた。PiPの単独切替だけでは停止せず、背景から戻る操作に伴う。ライブは停止後プレイヤー再起動まで不安定。LiveContainer 3.8.14、iOSの自動PiP設定はON。iOSの版は診断JSONへ自動記録する。

0.2.2は原因調査用で、音声セッション再設定・再生・PiP・配信・画面回転の処理を0.2.1から変更せず観測した。提供された診断を受け、0.2.3では復帰時の音声セッション再設定だけを撤去した。提供後に利用者から現在の動作が希望どおりとの確認を受けており、経緯と確認範囲を以下に記録する。

## 提供された実機ログの分析

iOS 26.7.3 / 0.2.2 build 7、152イベント。原本は利用者添付のJSONで、リポジトリへは取り込まない。以下は起動時の最初の診断イベントを0秒とした相対時刻。

| PiP復帰 | setActive相当区間 | pauseのWeb時刻 | pause受信 | buffer残秒 / readyState |
|---|---|---|---|---|
| 1 | 15.446–16.359秒 | 16.212秒 | 16.366秒 | 31.424 / 4 |
| 2 | 20.460–21.362秒 | 21.227秒 | 21.367秒 | 24.687 / 4 |
| 3 | 59.245–60.141秒 | 60.011秒 | 60.144秒 | 22.021 / 4 |
| 4 | 103.371–104.280秒 | 104.288秒 | 104.291秒 | 0 / 3 |
| 5 | 130.313–131.225秒 | 131.237秒 | 131.239秒 | 28.216 / 4 |

setActive相当区間は、setCategory直後のaudioCategorySetからsetActive完了後のaudioConfigureEndまで。各回約0.9秒かかり、pause受信は終了の3～14ms後。最初の3回のpauseはWeb側の時刻では処理中に発火しているため、受信時刻だけで「呼び出し終了後に発火」と解釈しない。

5回すべてrate=1、error=0。4回はreadyState=4かつ22秒以上のbufferがあり、単純なバッファ不足による停止では説明できない。4回目のbuffer=0については配信方式・再生種別がログにないため、同じ説明を当てはめない。

Nativeのinterruptionは7件すべてbeganで、Web側のplay/playing直前に記録されている。ホストアプリとWebKitの音声セッション競合を支持するが、割り込み元はこのJSONから特定できない。背景遷移時のinline動画のpauseは復帰時のpauseとは別の経路として扱う。inactiveだけの1サイクルでは新たなpauseを直接確認できず、Control Centerの症状すべての因果は確定していない。

0.2.3は、PiP復帰5回の反復した記録を根拠にsceneDidBecomeActiveからsetCategory/setActiveを除去した最小修正。起動時設定、観測、再生/PiP APIは維持。無条件playやライブ再起動は追加しない。自動PiP開始は別途未解決で、この修正で実現したとはしない。

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

0.2.2までの本家由来の`sceneDidBecomeActive`は復帰のたびに音声セッションをsetCategory/setActiveしていた。0.2.3でこの呼び出しを撤去し、同じ操作後の再生継続を比較する。ライブでは公開PlayerControllerのバッファ待ちが再生速度0を使う場合があるが、提供ログの上記5回はrate=1だった。

WKWebViewの`allowsPictureInPictureMediaPlayback`はPiPの許可で、自動inline PiPを必ず開始する設定ではない。AVKitの`canStartPictureInPictureAutomaticallyFromInline`相当の公開WK設定は確認できていない。今回のWebView全体の全画面化は、動画だけをAVKitの全画面へ移すものではない。Control Centerでも呼ばれるinactive通知にPiP要求を追加しない。

根拠:

- [Apple: 音声セッションの設定](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioSessionBasics/AudioSessionBasics.html)
- [Apple: 音声割り込み](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html)
- [WebKit: 公開WKWebViewConfiguration](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewConfiguration.h)
- [Apple: PiPと自動開始](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player)

2026-11-27、0.2.3/build 8提供後に利用者から「自動PiPは不要で、現状は理想どおりの動作」との確認を受けた。現在の挙動を維持し、自動PiPは対応対象から外す。この診断手順は、今後症状が再発した場合の調査用として保持する。

## 0.3.0/build 10の背景音声ログ

利用者の追加依頼で背景音声の1回だけの再開を試した版。2026-11-27提供、iOS 26.7.3、187件。原本は利用者添付の381371CF…JSONで、リポジトリには含めない。以下は起動時の最初のイベントからの相対時刻。

背景9サイクル、再開要求6回／成功6回／拒否0回、errorイベント4回。145件のWeb記録はすべてPiP=inline。Nativeの音声セッション設定は起動時の1回のみで、以前の復帰時再設定とは異なる。

| 再開成功の受信時刻 | errorの受信時刻 | Web時刻による間隔 | error / position |
|---|---|---|---|
| 60.016秒 | 60.070秒 | 55ms | 3 / 0 |
| 69.032秒 | 69.083秒 | 47ms | 3 / 0 |
| 130.145秒 | 130.200秒 | 56ms | 3 / 0 |
| 292.705秒 | 292.757秒 | 53ms | 3 / 0 |

error=3は[HTML仕様のMEDIA_ERR_DECODE](https://html.spec.whatwg.org/multipage/media.html#mediaerror)。playは拒否されず、その後デコード段階で失敗している。どのトラック・コーデック・内部デコーダーが失敗したかはこのログでは不明。70.641秒のemptiedでerrorが消えているため、その後のerror=0を成功反例とは扱わない。

400秒台の群は最初のhidden約2.450秒で位置増分0.007秒、次の約10.930秒では増分0秒。paused=false、rate=1、error=0、bufferAhead約33.8秒のまま固着した。後半ではhidden3.200／6.525／12.358秒に対し位置増分3.183／6.525／12.358秒と進行した。時計の進行だけで可聴音は証明できず、録画の全条件の成功も意味しない。

利用者報告の録画成功・ライブ失敗とは整合するが、ログにはライブ／録画・入力ソース型がなく、positionだけから断定しない。0.3.1はライブの強制再開を除外する安全策に限定し、内部原因を直した版とは扱わない。音声セッション再取得、反復play、強制シーク、Worker設定変更は追加しない。
