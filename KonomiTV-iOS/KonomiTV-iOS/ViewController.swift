import AVFoundation
import UIKit
import WebKit

/// KonomiTV を WKWebView で開く、アプリの唯一の画面。
///
/// 担うのは次の3点だけ (それ以外は KonomiTV 側の作りに任せる):
/// 1. WebView の設定 (インライン再生・PiP 許可・User-Agent の印)
/// 2. Web 側からの全画面の通知を受けて、ステータスバーを隠すこと
///    (縦向きから入る場合だけ、OS ごと横向きにする。既に横向きなら回さない)
/// 3. 開く URL の読み取り (設定アプリで変更可)
///
/// 全画面について:
/// Safari と違い、このアプリにはブラウザの UI が無い。残るのは iOS のステータスバーだけなので、
/// それを隠し、ウィンドウシーン自体の向きを横に切り替えれば「正規の全画面」になる。
/// 画面の向きを OS 側で切り替えるため、スクリーンショットもそのまま横向きで撮れる
/// (Web 版の擬似フルスクリーンのように、縦の枠の中に横向きの絵にはならない)。
final class ViewController: UIViewController {

    // MARK: - 定数

    /// 既定で開く KonomiTV (テレビ用ラッパーと同じ既定値)
    private static let defaultURLString = "https://192-168-100-6.local.konomi.tv:7000/"

    /// 設定アプリ側の項目キー (Settings.bundle/Root.plist と一致させる)
    private static let urlDefaultsKey = "konomi_url"

    /// Web 側との橋渡しの名前 (KonomiTV 側パッチの postMessage 先と一致させる)
    private static let bridgeName = "konomiNative"

    /// User-Agent に付ける印 (テレビ用ラッパーの KonomiTV-TV と同じ考え方)
    private static let userAgentMark = "KonomiTV-iOS/0.1"

    // MARK: - 状態

    private var webView: WKWebView!

    /// ネイティブ全画面中かどうか。ステータスバーとホームインジケーターの表示、
    /// それに WebView の制約 (通常時か全画面時か) が連動する。
    private var isNativeFullscreen = false {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            updateWebViewConstraints()
            updateContentInsetAdjustmentBehavior()
        }
    }

    // WebView の各辺の制約。辺ごとに「安全領域に合わせるもの」と「画面端に
    // 合わせるもの」の両方を用意し、向きと全画面かどうかで使う組を切り替える
    // (updateWebViewConstraints を参照)。
    private var topSafeConstraint: NSLayoutConstraint!
    private var topEdgeConstraint: NSLayoutConstraint!
    private var bottomSafeConstraint: NSLayoutConstraint!
    private var bottomEdgeConstraint: NSLayoutConstraint!
    private var leadingSafeConstraint: NSLayoutConstraint!
    private var leadingEdgeConstraint: NSLayoutConstraint!
    private var trailingSafeConstraint: NSLayoutConstraint!
    private var trailingEdgeConstraint: NSLayoutConstraint!

    /// 現在有効にしている制約の組 (同じ組なら入れ替えないための記録)
    private var appliedConstraints: [NSLayoutConstraint] = []

    /// この回の全画面で、入るときに画面の回転を行ったかどうか。
    /// 画面が既に横向きのときに入った場合は回転していないので、終了時も
    /// 回転まわりの後処理はせず、ステータスバーを出し直すだけでよい。
    /// 保険 (URL 監視) で終了させる場合も、この値で後処理を分ける。
    private var enteredWithRotation = false

    /// 最後に読み込んだ URL。設定で URL が変わっていたら読み直すために保持する。
    private var lastLoadedURLString: String?

    /// 全画面の終了後、通常時の許可向きへ戻すのを保留しているかどうか。
    /// 終了直後に許可向きを縦・横の両方へ戻すと、端末を横持ちしている場合は
    /// 姿勢に合わせて画面が横へ引き戻されてしまうため、端末が縦 (またはそれに
    /// 近い向き) を経由するまで縦だけに留める (2026-11-22 のユーザーの指定)。
    private var isOrientationRestorePending = false

    /// 端末の物理的な向きの変化の監視 (許可向きの復帰判定に使う)。
    private var deviceOrientationObserver: NSObjectProtocol?

    /// WebView の URL 変化の監視 (視聴ページを離れたときの全画面終了の保険に使う)。
    private var urlObservation: NSKeyValueObservation?

    // MARK: - ステータスバーと向き

    override var prefersStatusBarHidden: Bool {
        isNativeFullscreen
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        isNativeFullscreen
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    // MARK: - 画面の構築

    override func viewDidLoad() {
        super.viewDidLoad()
        // 安全領域 (ステータスバーの帯) の地の色は、KonomiTV のテーマ背景色 (#1e1310、
        // client 側の vuetify テーマ 'background') に合わせ、帯がページと同化して見えるようにする
        view.backgroundColor = UIColor(red: 0x1E / 255, green: 0x13 / 255, blue: 0x10 / 255, alpha: 1)

        let configuration = WKWebViewConfiguration()
        // 映像をページの中でそのまま再生する (iPhone 標準の動画だけ全画面にしない)
        configuration.allowsInlineMediaPlayback = true
        // HTML5 映像の PiP を許可する (WKWebView が iOS 9 から持つ仕組み)
        configuration.allowsPictureInPictureMediaPlayback = true
        // 再生のたびにタップを要求しない (KonomiTV 側の自動再生・切り替えを妨げない)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // User-Agent には元の文字列を残したまま印だけを後ろに足す。
        // 元の文字列を消すと、KonomiTV 側の iOS 判定 (端末種別やタッチ判定) が壊れるため。
        configuration.applicationNameForUserAgent = Self.userAgentMark
        // Web 側からの全画面通知を受ける
        configuration.userContentController.add(self, name: Self.bridgeName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // アプリ内で完結させるため、スワイプでの戻る/進むは無効にする
        webView.allowsBackForwardNavigationGestures = false
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // 制約は辺ごとに「安全領域」と「画面端」の2種類を用意し、向きと
        // 全画面かどうかで使う組を切り替える (updateWebViewConstraints)。
        // 横向きでは、左端から出てくるメニュー (サイドバー) がダイナミック
        // アイランドと重なって不便なため、左右だけ安全領域に合わせる。
        // 安全領域の余白は実質アイランドのある側にしか無いので、結果として
        // アイランド側だけが内側に入り、反対側は端まで使える。上下は画面端
        // まで使い、映像の高さは縮めない (2026-11-22 のユーザーの指定)。
        // 縦向きは従来どおりで、通常時は上端だけ安全領域、全画面時は四辺とも
        // 安全領域に合わせる。
        topSafeConstraint = webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        topEdgeConstraint = webView.topAnchor.constraint(equalTo: view.topAnchor)
        bottomSafeConstraint = webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bottomEdgeConstraint = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        leadingSafeConstraint = webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        leadingEdgeConstraint = webView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        trailingSafeConstraint = webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        trailingEdgeConstraint = webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        self.webView = webView
        updateWebViewConstraints()

        // 端末の物理的な向きの監視を始める (全画面終了後の許可向きの復帰判定に使う)。
        // 縦向きロックの状態はアプリからは読めないため、代わりに端末の姿勢そのものを見る。
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        deviceOrientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreOrientationLockIfReady()
        }

        // URL の変化を監視する (視聴ページを離れたのに全画面のまま残る場合の保険)。
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            self?.exitFullscreenIfLeftWatchPage()
        }

        loadHome()
    }

    /// 向きと全画面かどうかで、WebView の制約の組を切り替える。
    ///
    /// 組の選び方:
    /// - 横向き (通常時・全画面時とも): 左右は安全領域に合わせ、上下は画面端
    ///   まで使う。安全領域の左右の余白は実質ダイナミックアイランドのある側
    ///   にしか無いため、アイランド側だけがその分だけ内側に入り、左端から
    ///   出てくるメニューがアイランドに被らなくなる。反対側は端まで使え、
    ///   上下を端まで使うので映像の高さも縮まない。
    /// - 縦向き・通常時: 上端だけ安全領域に合わせ、他は画面端まで使う。
    ///   KonomiTV のページはブラウザ表示前提でステータスバー分の余白を持って
    ///   いないため、上端をそのまま貼るとヘッダー (ロゴや検索アイコンの行)
    ///   が時計・電波・電池の表示に重なってしまうため。
    /// - 縦向き・全画面時: 四辺とも安全領域の内側に置く (従来どおり)。
    /// 安全領域の外に出る余白は、ビューの背景色 (KonomiTV のテーマ色) で埋まる。
    ///
    /// 呼び出しの機会は、構築時 (viewDidLoad)、全画面の切り替え時
    /// (isNativeFullscreen の didSet)、画面表示時 (viewWillAppear)、回転時
    /// (viewWillTransition。回転後の大きさが渡されるので、それで向きを
    /// 判定する) の4箇所。同じ組になるときは何もしない。
    private func updateWebViewConstraints(for size: CGSize? = nil) {
        guard topSafeConstraint != nil else { return }
        let targetSize = size ?? view.bounds.size
        let selected: [NSLayoutConstraint]
        if targetSize.width > targetSize.height {
            selected = [topEdgeConstraint, bottomEdgeConstraint, leadingSafeConstraint, trailingSafeConstraint]
        } else if isNativeFullscreen {
            selected = [topSafeConstraint, bottomSafeConstraint, leadingSafeConstraint, trailingSafeConstraint]
        } else {
            selected = [topSafeConstraint, bottomEdgeConstraint, leadingEdgeConstraint, trailingEdgeConstraint]
        }
        guard selected != appliedConstraints else { return }
        NSLayoutConstraint.deactivate(appliedConstraints)
        NSLayoutConstraint.activate(selected)
        appliedConstraints = selected
        print("[KonomiTV-iOS] WebView constraints updated: landscape=\(targetSize.width > targetSize.height), fullscreen=\(isNativeFullscreen)")
    }

    /// 全画面の間だけ、ページの表示領域が安全領域ぶん自動で押し
    /// 上げられないようにする。
    ///
    /// WebView の枠自体は画面端まで届いていても、WKWebView には
    /// ページの表示領域 (スクロールビューの中身) を安全領域ぶん
    /// 内側へずらす既定の振る舞い (contentInsetAdjustmentBehavior
    /// = .automatic) がある。横向き全画面では、映像が上の端から
    /// 始まるのに下のホームバーぶん (約21pt) だけ押し上げられ、
    /// 下にだけテーマ色の帯が残って見えた (2026-11-22、実機の
    /// スクリーンショットを測って確認)。全画面の間だけ .never に
    /// してページを枠いっぱいに広げ、抜けたら既定 (.automatic) へ
    /// 戻す。通常時の表示には影響させない。
    /// 切り替えは isNativeFullscreen の didSet に連動させる。
    /// 開始・終了の経路 (橋渡し経由、URL 監視の保険経由) はすべて
    /// この値を経由するため、戻し忘れが起きない。
    private func updateContentInsetAdjustmentBehavior() {
        webView?.scrollView.contentInsetAdjustmentBehavior = isNativeFullscreen ? .never : .automatic
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 表示時点の大きさで、制約の組が向きに合っていることを確かめる
        // (横向きで起動した場合などの取りこぼし防止)
        updateWebViewConstraints()
        // 設定アプリで URL を変えて戻ってきたら、新しい URL を開き直す
        if let current = Self.homeURLString(), current != lastLoadedURLString, lastLoadedURLString != nil {
            loadHome()
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeName)
        if let deviceOrientationObserver {
            NotificationCenter.default.removeObserver(deviceOrientationObserver)
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        urlObservation = nil
    }

    // MARK: - URL の読み込み

    /// 設定アプリで変更された URL があればそれを、無ければ既定値を返す。
    /// バンドル ID はサイドロードの再署名で変わりうるため、URL はアプリの作りには組み込まず、
    /// 標準の UserDefaults (設定バンドル経由) から毎回読む。
    private static func homeURLString() -> String? {
        let saved = UserDefaults.standard.string(forKey: urlDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty {
            return saved
        }
        return defaultURLString
    }

    private func loadHome() {
        guard let urlString = Self.homeURLString(), let url = URL(string: urlString) else { return }
        lastLoadedURLString = urlString
        webView.load(URLRequest(url: url))
    }

    // MARK: - 全画面の開始・終了

    private func setNativeFullscreen(_ enter: Bool) {
        // 今の状態と同じ合図は無視する。同じ値の代入でも didSet が動いて
        // 向きの要求が二重に出てしまい、画面が余計に回る原因になるため。
        guard enter != isNativeFullscreen else {
            print("[KonomiTV-iOS] Fullscreen signal ignored (already \(enter ? "entered" : "exited"))")
            return
        }
        print("[KonomiTV-iOS] Fullscreen signal applied: enter=\(enter)")
        if enter {
            isOrientationRestorePending = false
            // 開始時点で画面が既に横向きかどうかで、入り方を分ける。
            // 既に横向きなら、端末を横にして開いて右の情報パネルを隠すだけで
            // 映像はほぼ画面いっぱいになっており、全画面のために回す必要は
            // ない (2026-11-22 の実機確認)。この場合は回転の要求も許可向きの
            // 変更も一切せず、ステータスバーを隠すだけにする。回転しなかった
            // ことは enteredWithRotation に残し、終了時の後処理を分ける。
            let current = view.window?.windowScene?.interfaceOrientation
            if let current, current.isLandscape {
                enteredWithRotation = false
                isNativeFullscreen = true
                print("[KonomiTV-iOS] Enter fullscreen: already landscape, status bar only (no rotation)")
            } else {
                enteredWithRotation = true
                isNativeFullscreen = true
                enterLandscape()
            }
        } else {
            let rotated = enteredWithRotation
            enteredWithRotation = false
            isNativeFullscreen = false
            if rotated {
                exitToPortrait()
            } else {
                // 回転して入っていないので、戻す回転も要らない。
                // ステータスバーを出し直すだけでよい (isNativeFullscreen の
                // 変更で連動済み)。許可向きの復帰保留も立てない。
                print("[KonomiTV-iOS] Exit fullscreen: no rotation was used, status bar only")
            }
        }
    }

    /// 全画面の開始 (縦向きから入る場合): 目標の横向きを1つ決め、
    /// まずその一方向だけを許可して回す。
    ///
    /// 目標の決め方 (2026-11-22 のユーザーの希望に合わせた仕様):
    /// - 端末が物理的に横向きなら、その姿勢に対応する側にする。
    /// - それ以外 (縦持ち・机に置いている等) は、決まった一方向
    ///   (充電口が右側に来る向き = landscapeRight) にする。
    /// 横向きの組 (左右両方) のまま要求すると、OS の選ぶ側と端末を回す向きが
    /// 合わないときに右横→左横へ反転して「2回回る」ため、最初は一方向に絞る。
    /// 横向きへ移り終えたら、許可向きを横向きの組へ広げて、端末をひっくり
    /// 返したときにも追従できるようにする (viewWillTransition で検知)。
    /// 縦向きロック中は iOS 自体が回転を止めるため、入った一方向に留まる
    /// (ロックの状態自体はアプリからは読めないが、結果として体感が一致する)。
    /// 画面が既に横向きの場合はここ自体が呼ばれない (setNativeFullscreen 参照)。
    private func enterLandscape() {
        let target = targetLandscapeOrientation()
        AppDelegate.orientationLock = Self.mask(for: target)
        requestGeometryUpdate(to: target, label: "enter landscape", retryOnFailure: false)
    }

    /// 全画面開始時の目標の横向きを決める。
    private func targetLandscapeOrientation() -> UIInterfaceOrientation {
        // 端末が物理的に横向きなら、その姿勢に対応する側にする。
        // UIDeviceOrientation と UIInterfaceOrientation は左右が逆に対応する
        // (端末を左へ倒すと、画面は右向きの横向きになる)。
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            // 縦持ち・顔を上に向けている等は、決まった一方向にする。
            return .landscapeRight
        }
    }

    /// 全画面の終了 (回して入った場合): 縦向きへの切り替えを OS に頼み、
    /// 許可向きの復帰は保留する。回さずに入った場合はここ自体が呼ばれず、
    /// ステータスバーを出し直すだけで終わる (setNativeFullscreen 参照)。
    ///
    /// 許可向きを広げるだけでは、いちど横向きに切り替えた画面は縦へ戻らない
    /// (2026-11-22 実機で確認)。そのため開始時と対称に、縦向きへの切り替え
    /// 自体を要求する。要求が断られた場合は、許可向きの再評価を促してから
    /// 1回だけ送り直す (別の向き切り替えや再評価と重なると断られることがある)。
    /// 通常時の許可向き (縦・横の両方) への復帰は、端末が縦を経由するまで
    /// 行わない (restoreOrientationLockIfReady を参照)。
    private func exitToPortrait() {
        AppDelegate.orientationLock = .portrait
        isOrientationRestorePending = true
        requestGeometryUpdate(to: .portrait, label: "exit to portrait", retryOnFailure: true)
        // 終了時点で画面も端末も既に縦なら、遷移を待たずに復帰できる場合がある。
        restoreOrientationLockIfReady()
    }

    /// ウィンドウシーンの向き切り替えを OS に頼む。
    /// CSS で画面だけを回す Web 版と違い、こちらは OS の向きが変わるので、
    /// スクリーンショットも横向きのまま撮れる。
    /// 失敗 (エラーコールバック) は記録に残し、retryOnFailure のときは
    /// 許可向きの再評価を先に促してから1回だけ送り直す。
    private func requestGeometryUpdate(to target: UIInterfaceOrientation, label: String, retryOnFailure: Bool) {
        if #available(iOS 16.0, *) {
            guard let scene = view.window?.windowScene else {
                print("[KonomiTV-iOS] Geometry update (\(label)) skipped: no window scene")
                return
            }
            let orientations = Self.mask(for: target)
            print("[KonomiTV-iOS] Geometry update requested: \(label)")
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                print("[KonomiTV-iOS] Geometry update (\(label)) rejected: \(error)")
                guard retryOnFailure else { return }
                // 許可向きの再評価を先に促してから、1回だけ送り直す。
                self.setNeedsUpdateOfSupportedInterfaceOrientations()
                print("[KonomiTV-iOS] Geometry update retrying once: \(label)")
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { retryError in
                    print("[KonomiTV-iOS] Geometry update (\(label)) retry rejected: \(retryError)")
                }
            }
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            // iOS 15 以前向けの従来手法 (対象 OS は 16 以降だが、保険として残す)
            UIDevice.current.setValue(target.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    /// 通常時の許可向き (縦・横の両方) への復帰を、条件がそろったときだけ行う。
    ///
    /// 条件: 全画面を終了済みで復帰が保留中で、画面が縦に戻っていて、かつ
    /// 端末の物理的な向きが横向きではないこと。
    /// 端末が横向きのままなら復帰しない。許可向きは縦だけに留まり、画面は
    /// 縦のままになる。これは「寝ながら縦で使いたいときは、姿勢だけで横へ
    /// 戻すな」というユーザーの指定 (2026-11-22) に沿った割り切りで、
    /// ロックを外して横持ちで使う場合は、端末を一度縦に経由するまで
    /// 横へは戻らない。判定の機会は、画面の回転の完了時 (viewWillTransition)
    /// と、端末の向きの変化の通知の2箇所。
    private func restoreOrientationLockIfReady() {
        guard isOrientationRestorePending, !isNativeFullscreen else { return }
        guard let orientation = view.window?.windowScene?.interfaceOrientation,
              orientation.isPortrait else {
            return
        }
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight {
            print("[KonomiTV-iOS] Orientation restore deferred: device is still landscape")
            return
        }
        isOrientationRestorePending = false
        AppDelegate.orientationLock = .allButUpsideDown
        print("[KonomiTV-iOS] Orientation lock restored to allButUpsideDown (device: \(deviceOrientation.rawValue))")
        refreshSupportedOrientations()
    }

    /// 許可向きの再評価を OS に促す (iOS の版に合わせて呼び分ける)。
    private func refreshSupportedOrientations() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // 回転後の大きさに合わせて、制約の組を新しい向きのものへ切り替える
        updateWebViewConstraints(for: size)
        coordinator.animate(alongsideTransition: nil) { _ in
            if self.isNativeFullscreen {
                // 横向きへ移り終えたら、許可向きを横向きの組 (左右両方) へ広げる。
                // 全画面中に端末をひっくり返しても追従できるようにするため。
                // ただし、回して入った場合だけ。既に横向きで回さずに入った
                // 場合は許可向きを一切変えない約束なので、ここでも触らない
                // (全画面中に端末を回して大きさが変わっても同様)。
                if self.enteredWithRotation, size.width > size.height, AppDelegate.orientationLock != .landscape {
                    AppDelegate.orientationLock = .landscape
                    print("[KonomiTV-iOS] Orientation lock widened to landscape (both sides)")
                    self.refreshSupportedOrientations()
                }
            } else if size.height >= size.width {
                // 縦へ戻り終えたら、条件つきで通常時の許可向きへ戻す。
                self.restoreOrientationLockIfReady()
            }
        }
    }

    /// 視聴ページを離れたのに全画面のままなら、保険として全画面を終了する。
    ///
    /// 視聴ページの URL は /tv/watch/<チャンネルID> と /videos/watch/<録画ID>
    /// の2形だけ (Web 側のルーター定義で確認済み) で、それ以外へ移ったことは
    /// 一意に判定できる。Web 側の終了の合図が出なかった場合の受け皿になる。
    private func exitFullscreenIfLeftWatchPage() {
        guard isNativeFullscreen, let path = webView.url?.path else { return }
        let isWatchPage = path.hasPrefix("/tv/watch/") || path.hasPrefix("/videos/watch/")
        if !isWatchPage {
            print("[KonomiTV-iOS] Left watch page (\(path)) while in fullscreen; exiting as a safeguard")
            setNativeFullscreen(false)
        }
    }

    /// 画面の向き1つに対応する許可向きの組を返す。
    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .landscape
        }
    }
}

// MARK: - Web 側からの通知 (橋渡し)

extension ViewController: WKScriptMessageHandler {

    /// KonomiTV 側から届く通知を受ける。
    /// 形式: {type: "fullscreen", enter: true/false}
    /// それ以外の形のメッセージは無視する (Web 側の将来の変更で落ちないように)。
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.bridgeName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }
        switch type {
        case "fullscreen":
            let enter = (body["enter"] as? Bool) ?? false
            // 受信の記録を残す (実機確認で、失敗した回と突き合わせられるように)。
            print("[KonomiTV-iOS] Bridge message received: fullscreen enter=\(enter)")
            setNativeFullscreen(enter)
        default:
            break
        }
    }
}

// MARK: - 読み込みの可否

extension ViewController: WKNavigationDelegate {

    /// このアプリは KonomiTV を開く専用なので、遷移はすべて許可する。
    /// (外部リンクの扱い分けは、必要になった時点でここに足す)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - JavaScript のダイアログ

extension ViewController: WKUIDelegate {

    /// alert / confirm / prompt をそのまま iOS のダイアログで出す。
    /// WKWebView は標準ではこれらを表示しないため、受け口が無いと Web 側が止まって見える。
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}
