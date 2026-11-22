# 作業記録 v0: iOS 用 KonomiTV ラッパーアプリの設計・土台 (2026-11-22)

本番 (録画サーバーの KonomiTV) には一切触れていない。成果物はすべて
`~/workspace/konomitv-ios-app/` 以下。実機・Mac ではまだ動かしていない。

## 要件 (ユーザー決定・申告)

1. 全画面ボタンを押したら iOS のステータスバーまで消える、正規の全画面。
2. PiP が動くこと。
3. 全画面のとき、スクリーンショットがそのまま正しい横向きの画像として撮れること
   (2026-11-22 追加申告。現行の擬似フルスクリーンは縦持ちのままコンテナだけを
   CSS で90度回すため、スクショが「縦の枠の中に横向きの絵」になる点を
   ユーザーは以前から気にしていた)。
- 実機への入れ方は、まず無料のサイドロードで試作する (2026-11-22 本人選択)。

## 作ったもの

- `KonomiTV-iOS/KonomiTV-iOS.xcodeproj` — 手書きの Xcode プロジェクト (共有スキーム付き)
- `KonomiTV-iOS/KonomiTV-iOS/AppDelegate.swift` — AVAudioSession (.playback / .moviePlayback)、向きの許可マスクの保持
- `KonomiTV-iOS/KonomiTV-iOS/SceneDelegate.swift` — ウィンドウ生成のみ
- `KonomiTV-iOS/KonomiTV-iOS/ViewController.swift` — WKWebView 構築、橋渡し (konomiNative)、ステータスバー・ホームインジケーター制御、向き制御、JS ダイアログ受け口、設定バンドルからの URL 読み取り
- `KonomiTV-iOS/KonomiTV-iOS/Info.plist` — 向き、ステータスバー、NSLocalNetworkUsageDescription、UIBackgroundModes=[audio]、起動画面 (UILaunchScreen + 背景色)
- `KonomiTV-iOS/KonomiTV-iOS/Settings.bundle/Root.plist` — 設定アプリで URL を変更する項目 (キー `konomi_url`)
- `KonomiTV-iOS/KonomiTV-iOS/Assets.xcassets` — AppIcon の枠 (画像は未投入) と起動画面の背景色
- `.github/workflows/build.yml` — macos-14 で署名なしビルド → 署名なし IPA を成果物に出す
- `konomitv-client-bridge.patch` — KonomiTV 側の橋渡し (案)
- `README.md` / `LICENSE` (テレビ用ラッパーと同じ MIT)

## 設計判断と根拠

### プロジェクト形式: .xcodeproj 手書き (生成方式にしない)

- 理由: Mac なしでも文章ファイルとして保守・差分確認ができる。XcodeGen 等の生成ツールを
  GitHub Actions に持ち込む手間と依存を避けられる。ファイル数が少ない (Swift 3本) ため
  手書きの project.pbxproj でも管理できる規模。
- 共有スキーム (`xcshareddata/xcschemes/KonomiTV-iOS.xcscheme`) を同梱した。
  これが無いと、まっさらなチェックアウトでは `xcodebuild -scheme` がスキームを見つけられない。

### 全画面: Web 側から通知 → アプリ側でステータスバー非表示 + シーンの向き変更

- アプリには Safari の UI が無いので、消すべきはステータスバーだけ。
  `prefersStatusBarHidden` を全画面フラグと連動させ、`setNeedsStatusBarAppearanceUpdate` で反映。
  あわせて `prefersHomeIndicatorAutoHidden` も連動させた。
- 向きは iOS 16+ の `UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))`。
  許可マスクは AppDelegate の `supportedInterfaceOrientationsFor` が返す静的値を
  全画面中は `.landscape` に切り替える。
- 終了時は「広い向きマスクをそのまま geometry update で要求しない」形にした
  (要求が断られるため)。許可マスクを戻して再評価を促すだけにし、回転は端末の向きに任せる。
- 対象 OS は iOS 16.0 以降 (IPHONEOS_DEPLOYMENT_TARGET=16.0)。iOS 15 以前の
  従来手法は保険としてコードに残したが、対象外のため実質は通らない。
- 要件3 (スクショが横向き) はこの方式の帰結: OS の向き自体が変わるため、
  キャプチャも横向きになる。Web 版の CSS 回転 (Watch.vue の
  `.watch-container--pseudo-fullscreen[data-pseudo-rotated="true"]` の rotate(90deg)) とは
  そこが違う。実機確認は必須 (下記)。

### PiP: WKWebView の標準 PiP + WebKit 独自 API への橋渡し

確認したコード根拠:

- `DocumentPiPManager.ts` (kc) 61〜68行: `init()` は
  `'documentPictureInPicture' in window` が false なら何もせず戻る。
  つまり WKWebView (Document PiP なし) では乗っ取りが起きず、標準経路が残る。
  乗っ取りの本体は同ファイル 71行〜で `video.requestPictureInPicture` の上書き。
- 同 217〜230行: 画質切り替え (`quality_end`) で映像要素が差し替わるため付け直している。
  橋渡しパッチの PiP 補いも同じ作法で付け直す形にした。
- `PlayerController.ts` (kc) 569行付近: 字幕は DPlayer の字幕コンテナ (DOM) で表示。
  483行〜: コメントは danmaku (DOM/canvas の重ね表示)。どちらも映像そのものには
  焼き込まれていない。→ PiP の小窓 (映像だけ) には字幕・コメントは付いていかない見込み。
- Apple の案内 (開発者向け文書 "Adopting Multitasking Enhancements on iPad:
  Picture in Picture Quick Start"): WKWebView は iOS 9 から PiP に対応し、
  止めるには `WKWebViewConfiguration.allowsPictureInPictureMediaPlayback` を false にする
  (裏返せば true で有効)。PiP の前提として Background Modes の
  「Audio, AirPlay and Picture in Picture」相当の設定が要る
  → Info.plist の `UIBackgroundModes=[audio]` と AVAudioSession .playback で対応。
- iOS の WebKit には標準の `HTMLVideoElement.requestPictureInPicture()` が無い
  (WebKit 独自の `webkitSetPresentationMode` / `webkitSupportsPresentationMode` を使う)。
  そのため、アプリ側の設定だけでは DPlayer の PiP ボタンが無反応になる可能性が高いと判断し、
  橋渡しパッチ側に補いを入れた。これが今回の設計で一番の不確実点。

→ 差し戻し条件 (WKWebView では PiP が原理的に動かない) には当たらない。
  WKWebView の PiP 自体は Apple の仕組みとして存在する。不確実なのは
  「KonomiTV の PiP ボタンから辿り着けるか」で、代替経路 (ネイティブ表示時の
  iOS 標準 PiP ボタン、再生中にアプリを離れた際の自動 PiP) も含め実機確認に回す。

### KonomiTV 側の全画面の橋渡し (パッチ案)

確認したコード根拠:

- `PlayerController.ts` (kc) 1579行〜 `setupFullscreenHandler()`:
  `fullScreen.request` (1604行〜) は body への Fullscreen API を試し、
  失敗・不在なら `enter_pseudo_fullscreen` (1589行〜、is_pseudo_fullscreen=true) に落とす。
  `fullScreen.cancel` (1636行〜) は擬似なら状態を戻すだけ。
  `fullScreen.isFullScreen` (1599行〜) は「擬似 or ブラウザ全画面」しか見ていない。
- パッチの変更点:
  - UA に `KonomiTV-iOS` を含む場合だけ分岐。request では状態フラグ
    (関数内ローカルの `is_native_fullscreen` と `player_store.is_fullscreen`) を立てて
    `webkit.messageHandlers.konomiNative` へ `{type:'fullscreen', enter:true}` を送る。
    isFullScreen の判定にもローカルフラグを足した (足さないと全画面中の再押下が
    「開始」に化けて、終了できなくなる)。
  - `is_pseudo_fullscreen` は立てない。立てると Watch.vue 側が擬似フルスクリーン専用の
    扱い (画面回転、右パネルやナビの非表示、専用終了ボタン) を始めてしまうため。
  - cancel では逆の通知を送る。
- パッチは kc ツリー基準で作成し、kc のコピーに対して試し当て
  (dry-run → 実際に当てて、手で入れた差分と一致すること) まで確認済み。
  ただし kc は本番より古い差分を含むため、パッチのヘッダーに「案」であることと、
  本番前提との突き合わせは実機投入フェーズで行う旨を明記した。本番には当てていない。

### PiP ボタンの振る舞い (現行コードから読めたこと)

- DPlayer の PiP ボタン自体の実装は kc ツリー内に無い (外部パッケージ
  `github:tsukumijima/DPlayer#v1.32.8`、package.json 28行)。
- KonomiTV 側から PiP を叩く経路は3つ:
  `KeyboardShortcutManager.ts` 263行 (キー E、`document.pictureInPictureEnabled` が
  true のときだけボタンをクリック)、`MediaSessionManager.ts` 152〜155行
  (メディアセッションの enterpictureinpicture、Chrome 前提のコメント付き)、
  `LiveEventManager.ts` 165行 (チャンネル切り替え時に PiP が残っていたら叩き直す)。
  いずれも標準 API 前提で、iOS ではそのままでは効かない見込み。
- よって「アプリ内で追加の橋渡しが要るか」への答えは「要る」で、その分を
  橋渡しパッチの DocumentPiPManager 側の変更として用意した。
  DPlayer のボタン表示自体が `document.pictureInPictureEnabled` で決まる場合は
  ボタンが出ない可能性が残る (実機確認項目)。

### User-Agent の印

- `WKWebViewConfiguration.applicationNameForUserAgent = "KonomiTV-iOS/0.1"` を使った。
  元の UA 文字列が残るため、KonomiTV 側の iOS / タッチ判定を壊さない。
  (`customUserAgent` で丸ごと差し替えると判定が壊れるおそれがあるため使わない。)
- テレビ用ラッパーは UA の後ろに `KonomiTV-TV/1.5` を足す方式 (MainActivity.java 60行)
  で、考え方は同じ。

### ATS と証明書

- Info.plist に ATS 例外は入れなかった。既定 URL は https で、テレビ用ラッパーも
  証明書検証を外す実装にはなっていない (MainActivity.java 67行、素の WebViewClient)
  ため、通常の検証で通る前提にした。実機で証明書エラーになる場合は未確認点として扱う。

### バンドル ID とサイドロード (2026-11-22 の決定の反映)

- 試作の本線は無料サイドロード。GitHub Actions は「署名なし IPA を成果物に出す」専用にし、
  署名あり配布 (TestFlight 等) は将来の有料プラン用に別ワークフローへ分ける方針を
  build.yml の冒頭コメントと README に明記した。
- AltStore は同じ Wi-Fi 上で AltServer を動かすパソコンが要る。SideStore は
  初期設定 (端末側の設定作り) が要る代わりに、その後の更新は端末側でできる。
  どちらも無料 Apple ID の署名は7日で切れ、更新が要る。README に比較表で整理した。
- バンドル ID はプロジェクトに `jp.tatsuya0902.konomitv.ios` と置いてあるが、
  再署名で置き換わる前提。アプリの作りは固定 ID に依存していない
  (App Groups・キーチェーン共有・エンタイトルメントは不使用。設定は標準 UserDefaults のみ)。
  注意点として、バンドル ID が変わると UserDefaults (開く URL の設定) は引き継がれない。
  README に「入れ直しは同じバンドル ID のまま上書き」を明記した。

## ローカルで確認したこと (Mac・実機なしの範囲)

- build.yml: YAML として読み込み可。
- Info.plist / Settings.bundle の Root.plist: plist として読み込み可。
- Assets の各 Contents.json: JSON として読み込み可。
- xcscheme: XML として読み込み可。
- project.pbxproj: 波かっこ・丸かっこの対応が取れていること、参照 ID の目視確認。
- Swift 3本: 目視確認 (明らかな構文ミス、型の食い違い、iOS 16 API の availability 囲い)。
  この VM には swiftc / xcodebuild が無いため、コンパイル確認はできていない。
- 橋渡しパッチ: kc ツリーのコピーへ試し当て成功 (上記)。

## 未確認点 (実機・Mac ビルドでしか分からないこと)

1. GitHub Actions でのビルド成否そのもの (手書き pbxproj の正しさはここで初めて確定する)。
   AppIcon の画像が未投入のため、警告が出る見込み (エラーになるかは未確認)。
2. 実機で KonomiTV が表示できるか。特に証明書の検証と、ローカルネットワーク許可の
   ダイアログ周り (NSLocalNetworkUsageDescription を入れてあるが、許可が必要な
   経路かどうかは構成依存)。
3. 全画面の橋渡しが一往復するか (入る・出る)。requestGeometryUpdate が
   KonomiTV の画面構成 (横向き固定の要求と競合しないか) と合うか。
4. **要件3: 全画面中に撮ったスクリーンショットが、写真アプリで横向きのまま見られるか。**
5. PiP の起動経路: 橋渡しパッチの補いで DPlayer の PiP ボタンから出るか。
   出ない場合の代替経路 (iOS 標準ボタン / 自動 PiP) が効くか。
   画質切り替え後も補いが付け直されるか。
6. PiP 中の音声の扱いと、アプリに戻ったときの復帰 (映像要素が PiP から戻るか)。
7. 設定アプリで URL を変えた際の反映 (viewWillAppear での再読み込み判定)。

## 次に決めてほしいこと

- 署名の方式は「無料サイドロードで試作」で決定済み (2026-11-22)。
  次の判断は、リポジトリを GitHub に置いて Actions を回してよいか (push のゴーサイン)。
  その先は実機確認の結果を見て、有料プランへ進むかどうか。
