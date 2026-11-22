# ビルド結果 v1（2026-11-22、途中で停止）

## ここまで実施したこと

- gh CLI の認証確認：tatsuya0902 として認証済み（repo 権限あり）。
- 同名リポジトリ `tatsuya0902/konomitv-ios-app` が存在しないことを確認。
- コミット前の混入物チェックを実施（署名ファイル・認証情報類の混入がない前提でコミットへ進めた）。
- ローカルで git リポジトリを初期化し、初回コミットを作成した。
  - コミット ID: `6c48729f15aec01d0840f86c986d8bf51aca11a5`
  - 内容: 土台一式15ファイル（Swift ソース、xcodeproj、ワークフロー、README、橋渡しパッチ、work-result-v0.md）

## 停止した理由

- 初回コミット直後、この作業フォルダの中身が実行リスクチェックに引っかかった旨のシステム通知を受けた。
- 通知の指示により、この中身に対するこれ以上の処理（GitHub への push、Actions でのビルド実行など、コードを実行しうる操作）は、ユーザーの明示的なゴーサインがあるまで行わないことになった。

## 未実施（残っていること）

- GitHub リポジトリの作成（private）と push：未実施。リポジトリ URL はまだ無い。
- GitHub Actions の実行確認：未実施（実行 ID なし）。
- 署名なし IPA の取得確認：未実施（成果物はまだ無い）。
- ビルドの成否そのものが未確認。Swift のコンパイル可否、プロジェクト形式を Xcode が読めるかも未確認のまま。

## 次に必要なこと

- ユーザー本人から「この一式を GitHub に push し、Actions でビルドを回してよい」ことの再確認（今回はコードがクラウド上で実行される点を含む）。
- 許可が得られれば、リポジトリ作成（private）→ push → Actions 結果確認 → 成果物（署名なし IPA）のダウンロード確認、の順で再開する。

## 本番への接触

なし。録画サーバーの KonomiTV には一切触れていない。実機へのインストールも行っていない。

---

# 再開後の記録（2026-11-22、ビルド担当・再開）

ユーザーの再確認（「この一式を GitHub へ push し、クラウドでビルドしてよい」、コードがクラウドで実行される点を含む）を受けて再開した。

## 実施したこと

- 非公開リポジトリを作成し、コード一式の push まで完了した。
  - リポジトリ: https://github.com/tatsuya0902/konomitv-ios-app （private）
  - push 済みコミット: `8ee87a2`（土台一式。後述の理由で初回コミット `6c48729` から履歴を作り直したもの）、`c8166a1`（この記録ファイル）、`4f8f5a5`（ワークフロー原本の保管）
- ワークフローファイル（`.github/workflows/build.yml`）だけは push できなかった。理由は下記の関門のとおり。
  - そのため、履歴からワークフローファイルを除き、原本はリポジトリ内の `workflows-source/build.yml` に保管した（説明は `workflows-source/README.md`）。

## 関門（ご本人の操作が要る）

- この VM の gh トークンの権限は `gist, read:org, repo` で、`workflow` が無い。
- ワークフローファイルを含む push は GitHub に拒否された（「OAuth App に workflow スコープなしでワークフローを作成・更新できない」という応答）。
- 代替策も確認済みで、いずれも同じ関門に当たった。
  - SSH 経由の push：この VM の SSH 鍵が GitHub アカウントに登録されておらず、認証エラー。
  - API 経由のファイル作成：通常ファイルは読み書きできるのに、`.github` 配下だけ 404 になる（権限が無い対象は存在しない扱いになる GitHub の仕様）。
- つまり、Actions を回すには次のどちらかが要る。
  1. gh の権限追加を本人が承認する（`gh auth refresh -h github.com -s workflow` を始めると表示されるコードを、本人が github.com/login/device で入力する）。承認後にこちらで `workflows-source/build.yml` を `.github/workflows/build.yml` へ移して push すれば、Actions が走る。
  2. 本人が GitHub の Web 画面で `.github/workflows/build.yml` を新規作成し、`workflows-source/build.yml` の中身を貼ってコミットする。そのコミットで Actions が走る。

## 未実施（関門の先）

- GitHub Actions の実行：未実施（実行 ID なし）。ビルドの成否はまだ分からない。
- 署名なし IPA の取得：未実施（成果物はまだ無い）。

## 本番への接触（再開分）

なし。録画サーバーの KonomiTV には一切触れていない。実機へのインストールも行っていない。

---

# 最終段階の記録（2026-11-22、ビルド担当・最終段階）

ユーザーがデバイスコードで承認し、gh トークンに workflow 権限が追加された（scopes: gist, read:org, repo, workflow。担当側でも実測確認）ため、関門は解消し、残りを実施した。

## 実施したこと

- `workflows-source/build.yml` を本来の場所 `.github/workflows/build.yml` へ配置してコミット・push した（コミット `043d6cb`）。workflows-source 側の保管と説明はそのまま残してある。
- GitHub Actions の実行結果：
  - 1回目（実行 ID `44970685755`）：失敗。ジョブが1秒で取り消された。理由はアノテーション「The configuration 'macos-14-arm64-us-xl' is not supported」で、指定した `macos-14` ランナー構成が未対応だったため。
  - 直した点：`runs-on` を `macos-14` から `macos-latest` へ変更（`.github/workflows/build.yml` と `workflows-source/build.yml` の両方。コミット `c9e197b`）。
  - 2回目（実行 ID `44970711568`）：**成功**。全ステップ（チェックアウト、Xcode バージョン表示、署名なしビルド、IPA のパッケージ、成果物のアップロード）が通過した。所要はジョブ約19秒。コード自体（Swift・プロジェクト設定）の修正は不要だった。
- 成果物（署名なし IPA）の取得確認：
  - `gh run download` で実際に取得できた。置き場所：`~/workspace/konomitv-ios-app/build-output/KonomiTV-iOS-unsigned.ipa`（27,644 バイト）。
  - 中身を確認済み：`Payload/KonomiTV-iOS.app` が入っており、実行ファイル `KonomiTV-iOS`（Mach-O 64-bit arm64、約129KB）、Info.plist、Assets.car、Settings.bundle、PkgInfo が揃っている。
  - Actions 側にも成果物 `KonomiTV-iOS-unsigned-ipa` として残っている。

## 残っていること（この担当の範囲外）

- 実機へのインストール（無料サイドロード）と実機での動作確認は未実施。ビルドが通ったことと、実機で動くことは別である。
- AppIcon は未投入のまま（ビルドは警告なしで通過したが、アイコン画像自体はまだ無い）。

## 本番への接触（最終段階分）

なし。録画サーバーの KonomiTV には一切触れていない。実機へのインストールも行っていない。

# LiveContainer 起動失敗の修正（2026-11-22、不具合修正担当）

ユーザーが署名なし IPA を LiveContainer に取り込んで実行したところ、起動時にエラーになった：
"Failed to map /var/mobile/Containers/Data/Application/.../Documents/Applications/jp.tatsuya0902.konomitv.ios.app/(null): Bad file descriptor"

## 裏取り結果（原因は親担当の読みどおりで確定）

- ソースの Info.plist（KonomiTV-iOS/KonomiTV-iOS/Info.plist）に CFBundleExecutable が無い。
- 前回のビルド済み IPA（実行 ID 44970711568）を展開しても、アプリ本体の Info.plist に CFBundleExecutable が無い（キー一覧を実測）。実行ファイル KonomiTV-iOS（Mach-O arm64、131,448 バイト）自体は存在する。
- project.pbxproj は GENERATE_INFOPLIST_FILE = NO（Debug/Release 両方）のため、Xcode が自動では補わない。
- つまり LiveContainer が CFBundleExecutable から実行ファイル名を引けず (null) になり、マップに失敗した、という読みで確定。
- ついでに点検したところ、Xcode が通常自動生成する標準キーのうち CFBundleDevelopmentRegion も欠けていた（他の標準キー＝CFBundleName / Identifier / InfoDictionaryVersion / PackageType / ShortVersionString / Version / DisplayName は揃っていた）。

## 直した内容

- ソース Info.plist に2キーを追加した（コミット `f664207`）：
  - CFBundleExecutable = $(EXECUTABLE_NAME)（本題の修正）
  - CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)（標準キーの欠け。憶測ではなく、Xcode の自動生成テンプレートに必ず入るキーのため）
- コード（Swift・プロジェクト設定）への変更はなし。

## ビルドと実物の確認

- GitHub Actions 実行 ID `44971311791`：**成功**（全ステップ通過。直し直しの再実行は不要だった）。
- 新しい署名なし IPA を gh run download で取得し、build-output/KonomiTV-iOS-unsigned.ipa を差し替えた（27,684 バイト。差し替え前は 27,644 バイト）。
- 新しい IPA を展開して実物で確認済み：Info.plist に CFBundleExecutable = KonomiTV-iOS が入っており、同名の実行ファイルも存在する。CFBundleDevelopmentRegion = en も入った。

## 残っていること

- 実機（LiveContainer）で起動するかは、ユーザーの次の試行待ち。こちらでは実機確認はしていない。
- AppIcon は未投入のまま（従来どおり）。

## 本番への接触（不具合修正分）

なし。録画サーバーの KonomiTV には一切触れていない。

---

# 表示修正：ステータスバーとヘッダーの重なり（2026-11-22）

## 発端

アプリは LiveContainer で起動し、KonomiTV のトップ画面と番組データの表示まで実機確認できた（成功）。その上でユーザーから新しい指摘：通常画面で iOS のステータスバー（時計・電波・電池）が KonomiTV のヘッダー（ロゴや検索アイコンの行）に重なって表示される。

## 裏取り結果

- ViewController.swift の viewDidLoad で、WKWebView の制約が view の四辺ぴったり（topAnchor = view.topAnchor 等）になっており、安全領域（safe area）を無視していた。Web ページの先頭がステータスバーの下に潜る作りで、原因は親担当の読みどおり確定。
- isNativeFullscreen の didSet は、ステータスバーとホームインジケーターの更新だけで、制約の切り替えはしていなかった。
- ステータスバーの帯の地の色に使う #1e1310 は、KonomiTV client 側の vuetify テーマ 'background': '#1e1310'（client/src/plugins/vuetify.ts）と一致することを確認した。

## 直した内容

- ViewController.swift のみ変更（コミット `f2f0d45`）：
  - 通常時：WebView の上端を view.safeAreaLayoutGuide.topAnchor に合わせる制約へ変更。左右・下端は従来どおり画面端（下端は実機表示で問題が出ていないため触らない）。横向きの通常時も安全領域に追従する。
  - 全画面時（isNativeFullscreen = true）：従来どおり上端まで広げる。制約は通常用と全画面用の2組を保持し、isNativeFullscreen の didSet から activate/deactivate で切り替えるようにした。
  - view.backgroundColor を黒からテーマ背景色 #1e1310 へ変更し、ステータスバーの帯がページと同化して見えるようにした。WebView 自体の背景色は現状維持。

## ビルドと IPA

- GitHub Actions 実行 ID `44971597880`：**成功**（全ステップ通過。直し直しの再実行は不要だった）。
- 新しい署名なし IPA を gh run download で取得し、build-output/KonomiTV-iOS-unsigned.ipa を差し替えた（28,318 バイト。差し替え前は 27,684 バイト）。
- 新しい IPA を展開して確認済み：前回の修正（CFBundleExecutable = KonomiTV-iOS）も維持されている。

## 残っていること

- 実機で重なりが解消したかは、ユーザーの次の試行待ち。こちらでは実機確認はしていない。

## 本番への接触（表示修正分）

なし。録画サーバーの KonomiTV には一切触れていない。

---

# 追記：アプリアイコンの設定（2026-11-22 再開分）

ユーザーの再確認（「アイコン入りでGitHubへpushし、クラウドでビルドしてよい」、クラウドでコードが実行される点を含む）を受けて再開した。

## 裏取りと点検の結果

- Contents.json は単一サイズ方式に差し替え済みで、`AppIcon-1024.png`（universal / ios / 1024x1024）を指していることを確認した。
- アイコン画像は 1024×1024・RGB・透明なしで、仕様どおりだった（元絵は KonomiTV 公式アイコン、角の透明部分は元の背景グラデーションを再現して埋めたもの）。
- 基本項目の点検（変更なし）：
  - 表示名：CFBundleDisplayName = KonomiTV、あり。
  - 起動画面：UILaunchScreen が UIColorName = LaunchBackground を指し、LaunchBackground.colorset（暗いグレー）も存在する。
  - バージョン表記：MARKETING_VERSION = 0.1 / CURRENT_PROJECT_VERSION = 1 で、Info.plist から参照されている。ビルド後の実物でも 0.1 / 1 を確認した。

## 実施したこと

- アイコンの2点（Contents.json と AppIcon-1024.png）をコミット `028b009` で push した。
- GitHub Actions 実行 ID `44972216378`：**成功**（全ステップ通過。再実行は不要だった）。

## 新しい IPA とアイコン取り込みの確認

- 署名なし IPA を gh run download で取得し、build-output/KonomiTV-iOS-unsigned.ipa を差し替えた（144,622 バイト。前回は 28,318 バイトで、増分はアイコン素材分）。
- 展開した .app で実物確認済み：
  - Info.plist の CFBundleIcons → CFBundlePrimaryIcon に CFBundleIconName = AppIcon と CFBundleIconFiles = [AppIcon60x60] が入っている。
  - .app 直下に AppIcon60x60@2x.png（120×120）と AppIcon76x76@2x~ipad.png（152×152）が生成されている。
  - Assets.car（129,656 バイト）が存在し、AppIcon の名前を含む。
  - 前回までの修正（CFBundleExecutable = KonomiTV-iOS、表示名 KonomiTV、バージョン 0.1 / 1）も維持されている。

## 残っていること

- 実機でアイコンが表示されるかは、ユーザーの次の試行待ち。こちらでは実機確認はしていない。

## 本番への接触（アプリアイコン分）

なし。録画サーバーの KonomiTV には一切触れていない。

---

# ビルド記録 v1 追記（2026-11-22、全画面の終了時に縦へ戻らない問題の修正）

## 発端

実機で「全画面から戻ろうとしても、ステータスバーや周りの表示は戻るのに画面の向きだけ横のまま残る」という報告があった（2026-11-22）。原因はアプリ側の全画面終了処理で、終了時は許可向きを広げるだけで、縦向きへの切り替え自体を OS へ要求していなかったこと。

## 変更内容

- 対象は `KonomiTV-iOS/KonomiTV-iOS/ViewController.swift` のみ（親担当が編集、ビルド担当が git diff で内容を確認してからコミットした。想定外の変更は混ざっていなかった）。
  - 終了時は許可向きを `.portrait` にし、新設した `requestPortrait()` で開始時と対称に縦向きへの切り替えを OS へ要求する（iOS 16 以降は `requestGeometryUpdate`、未満は従来手法）。
  - `viewWillTransition` を追加し、縦へ戻り終えたら通常時の許可向き（`.allButUpsideDown`）へ復帰させる（戻し忘れると通常画面でも縦固定になるため）。

## 実施したこと

- 上記の変更をコミット `8bcc988` で push した。
- GitHub Actions 実行 ID `44976163915`：**成功**（全ステップ通過。再実行は不要だった）。

## 新しい IPA と基本項目の確認

- 署名なし IPA を gh run download で取得し、build-output/KonomiTV-iOS-unsigned.ipa を差し替えた（145,500 バイト。前回は 144,622 バイト）。
- 展開した .app で実物確認済み：
  - CFBundleExecutable = KonomiTV-iOS（実行ファイルは arm64 の Mach-O で存在）。
  - 表示名 CFBundleDisplayName = KonomiTV、バージョン 0.1 / 1 を維持。
  - アイコン：CFBundleIcons が AppIcon を指し、AppIcon60x60@2x.png と AppIcon76x76@2x~ipad.png が生成されている。
  - 今回の直しの目印（"Geometry update (portrait)" の文字列）が実行ファイルに含まれることを確認した。

## 残っていること

- 実機で全画面から縦へ戻れるかは、ユーザーの次の試行待ち。こちらでは実機確認はしていない。

## 本番への接触（今回分）

なし。録画サーバーの KonomiTV には一切触れていない。
