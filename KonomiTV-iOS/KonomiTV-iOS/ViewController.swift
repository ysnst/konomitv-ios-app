import AVFoundation
import CoreFoundation
import UIKit
import WebKit

/// KonomiTV を WKWebView で開く、アプリの唯一の画面。
///
/// 担うのは次の3点だけ (それ以外は KonomiTV 側の作りに任せる):
/// 1. WebView の設定 (インライン再生・PiP 許可・User-Agent の印)
/// 2. Web 側からの全画面の通知を受けて、ステータスバーを隠すこと
///    (縦向きから入る場合だけ、OS ごと横向きにする。既に横向きなら回さない)
/// 3. 開く URL の読み取り (未設定ならアプリ内で入力画面を出し、設定アプリでも変更可)
///
/// 全画面について:
/// Safari と違い、このアプリにはブラウザの UI が無い。残るのは iOS のステータスバーだけなので、
/// それを隠し、ウィンドウシーン自体の向きを横に切り替えれば「正規の全画面」になる。
/// 画面の向きを OS 側で切り替えるため、スクリーンショットもそのまま横向きで撮れる
/// (Web 版の擬似フルスクリーンのように、縦の枠の中に横向きの絵にはならない)。
final class ViewController: UIViewController {

    // MARK: - 定数

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

    /// 遅れて返った回転エラーから、次の全画面操作を巻き戻さないための世代。
    private var fullscreenGeneration = 0

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

    /// URL 未設定のときに出す入力画面と、その入力欄 (必要なときに組み立てる)。
    private var urlInputView: UIView?
    private var urlTextField: UITextField?

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
        // 画面端からの横スワイプで戻る/進む操作を使えるようにする
        // (視聴画面から録画一覧へ戻るため。2026-11-22 のユーザーの要望)
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // 制約は辺ごとに「安全領域」と「画面端」の2種類を用意し、向きと
        // 全画面かどうかで使う組を切り替える (updateWebViewConstraints)。
        // 横向きでは、左端から出てくるメニュー (サイドバー) がダイナミック
        // アイランドと重なって不便なため、左右だけ安全領域に合わせる。
        // 安全領域の余白は実質アイランドのある側にしか無いので、結果として
        // アイランド側だけが内側に入り、反対側は端まで使える。上下は画面端
        // まで使い、映像の高さは縮めない (2026-11-22 のユーザーの指定)。
        // 通常の縦向きでは上端を安全領域へ合わせ、全画面中は四辺とも画面端へ広げる。
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

        loadHomeOrShowURLInput()
    }

    /// 向きと全画面かどうかで、WebView の制約の組を切り替える。
    ///
    /// 組の選び方:
    /// - 全画面時: 四辺とも画面端まで使う。
    /// - 横向き・通常時: 左右は安全領域に合わせ、上下は画面端
    ///   まで使う。安全領域の左右の余白は実質ダイナミックアイランドのある側
    ///   にしか無いため、アイランド側だけがその分だけ内側に入り、左端から
    ///   出てくるメニューがアイランドに被らなくなる。反対側は端まで使え、
    ///   上下を端まで使うので映像の高さも縮まない。
    /// - 縦向き・通常時: 上端だけ安全領域に合わせ、他は画面端まで使う。
    ///   KonomiTV のページはブラウザ表示前提でステータスバー分の余白を持って
    ///   いないため、上端をそのまま貼るとヘッダー (ロゴや検索アイコンの行)
    ///   が時計・電波・電池の表示に重なってしまうため。
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
        if isNativeFullscreen {
            // 全画面では WebView を四辺まで広げる。操作部品の安全領域は Web 側に任せる。
            selected = [topEdgeConstraint, bottomEdgeConstraint, leadingEdgeConstraint, trailingEdgeConstraint]
        } else if targetSize.width > targetSize.height {
            selected = [topEdgeConstraint, bottomEdgeConstraint, leadingSafeConstraint, trailingSafeConstraint]
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
        // 設定アプリで URL を変えて戻ってきたら、新しい URL を開き直す。
        // 空に変えられていたら、入力画面を出す。
        if Self.homeURLString() == nil {
            showURLInput()
        } else if let current = Self.homeURLString(), current != lastLoadedURLString {
            hideURLInput()
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

    /// 保存されている URL を返す。未設定 (保存値が無い・空) なら nil。
    /// 既定の URL は持たない。初めて使うときは、入力画面で入れてもらう。
    /// バンドル ID はサイドロードの再署名で変わりうるため、URL はアプリの作りには組み込まず、
    /// 標準の UserDefaults (設定バンドル経由) から毎回読む。
    private static func homeURLString() -> String? {
        guard let saved = UserDefaults.standard.string(forKey: urlDefaultsKey) else { return nil }
        return normalizedURLString(saved)
    }

    /// 入力された URL を整える。前後の空白を取り除き、方式 (https:// 等) が
    /// 付いていなければ https:// を補う。空なら nil (保存しない)。
    private static func normalizedURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: normalized),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return normalized
    }

    /// 保存されている URL があれば開き、無ければ入力画面を出す。
    private func loadHomeOrShowURLInput() {
        if Self.homeURLString() != nil {
            hideURLInput()
            loadHome()
        } else {
            showURLInput()
        }
    }

    private func loadHome() {
        guard let urlString = Self.homeURLString(), let url = URL(string: urlString) else { return }
        resetFullscreen()
        installFullscreenScript(for: url)
        lastLoadedURLString = urlString
        webView.load(URLRequest(url: url))
    }

    /// 接続先変更時にスクリプトも作り直す。認証・外部サイトは JS 冒頭の origin 判定で除外する。
    private func installFullscreenScript(for url: URL) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        guard let resource = Bundle.main.url(forResource: "FullscreenBridge", withExtension: "js"),
              let source = try? String(contentsOf: resource, encoding: .utf8),
              var origin = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            print("[KonomiTV-iOS] Fullscreen bridge resource unavailable")
            return
        }
        origin.path = ""
        origin.query = nil
        origin.fragment = nil
        // URL を JavaScript 文字列へ直接連結せず JSON で符号化する。
        guard let originString = origin.string,
              let data = try? JSONSerialization.data(withJSONObject: [originString]),
              let argument = String(data: data, encoding: .utf8) else { return }
        controller.addUserScript(WKUserScript(
            source: "\(source)(\(argument)[0]);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
    }

    /// Web とネイティブの両方を通常表示へ戻す。再生・Cookie・現在位置は変更しない。
    func resetFullscreen() {
        if isTrustedWatchURL(webView?.url) {
            webView?.evaluateJavaScript("document.dispatchEvent(new Event('konomi-native-fullscreen-reset'))", completionHandler: nil)
        }
        setNativeFullscreen(false)
    }

    private func isTrustedOriginURL(_ url: URL?) -> Bool {
        guard let url, let saved = Self.homeURLString(), let home = URL(string: saved),
              url.scheme?.lowercased() == home.scheme?.lowercased(),
              url.host?.lowercased() == home.host?.lowercased(),
              (url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)) == (home.port ?? (home.scheme?.lowercased() == "https" ? 443 : 80)) else { return false }
        return true
    }

    private func isTrustedWatchURL(_ url: URL?) -> Bool {
        guard isTrustedOriginURL(url), let url else { return false }
        return url.path.range(of: "^/(tv|videos)/watch/[^/]+/?$", options: .regularExpression) != nil
    }

    // MARK: - URL の入力画面

    /// URL の入力画面を出す。必要なときにだけ組み立てる。
    /// 設定アプリ側で入れられた値があれば、それを入力欄の初期値として見せる。
    private func showURLInput() {
        resetFullscreen()
        if urlInputView == nil {
            buildURLInputView()
        }
        urlTextField?.text = UserDefaults.standard.string(forKey: Self.urlDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let urlInputView {
            urlInputView.isHidden = false
            view.bringSubviewToFront(urlInputView)
        }
    }

    private func hideURLInput() {
        urlInputView?.isHidden = true
    }

    /// 入力画面は、案内文・入力欄・「開く」ボタンだけの簡素な作りにする。
    /// 地の色は通常画面と同じテーマ色に合わせる。
    private func buildURLInputView() {
        let container = UIView()
        container.backgroundColor = view.backgroundColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "KonomiTV の URL を入力してください"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textField = UITextField()
        textField.placeholder = "https://..."
        textField.textColor = .white
        textField.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        textField.layer.cornerRadius = 8
        textField.keyboardType = .URL
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .go
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(openEnteredURL), for: .editingDidEndOnExit)

        let openButton = UIButton(type: .system)
        openButton.setTitle("開く", for: .normal)
        openButton.setTitleColor(.white, for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        openButton.layer.cornerRadius = 8
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.addTarget(self, action: #selector(openEnteredURL), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, textField, openButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            textField.heightAnchor.constraint(equalToConstant: 44),
            openButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        urlInputView = container
        urlTextField = textField
    }

    /// 入力された URL を保存して、そのまま開く。
    /// 空なら保存せず、入力画面のままにする。
    @objc private func openEnteredURL() {
        guard let text = urlTextField?.text,
              let normalized = Self.normalizedURLString(text),
              URL(string: normalized) != nil else {
            return
        }
        urlTextField?.resignFirstResponder()
        UserDefaults.standard.set(normalized, forKey: Self.urlDefaultsKey)
        print("[KonomiTV-iOS] URL saved from input screen")
        hideURLInput()
        loadHome()
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
        fullscreenGeneration += 1
        if enter {
            isOrientationRestorePending = false
            // 既に横向きなら余分な回転要求を出さず、横向きの許可だけ固定する。
            let current = view.window?.windowScene?.interfaceOrientation
            if let current, current.isLandscape {
                // 横向きで開始しても、解除時には必ず縦へ戻す。
                isNativeFullscreen = true
                AppDelegate.orientationLock = .landscape
                refreshSupportedOrientations()
            } else {
                isNativeFullscreen = true
                enterLandscape()
            }
        } else {
            isNativeFullscreen = false
            exitToPortrait()
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

    /// 全画面の終了時は開始姿勢にかかわらず縦向きへ戻す。
    /// 許可向きの復帰は保留する。
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
                if isNativeFullscreen { resetFullscreen() }
                return
            }
            let orientations = Self.mask(for: target)
            let generation = fullscreenGeneration
            setNeedsUpdateOfSupportedInterfaceOrientations()
            print("[KonomiTV-iOS] Geometry update requested: \(label)")
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                guard generation == self.fullscreenGeneration else { return }
                print("[KonomiTV-iOS] Geometry update (\(label)) rejected: \(error)")
                guard retryOnFailure else {
                    self.resetFullscreen()
                    return
                }
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
                if size.width > size.height, AppDelegate.orientationLock != .landscape {
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
        guard isNativeFullscreen else { return }
        if !isTrustedWatchURL(webView.url) {
            print("[KonomiTV-iOS] Left trusted watch page; exiting fullscreen")
            resetFullscreen()
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
              message.webView === webView,
              message.frameInfo.isMainFrame,
              isTrustedOriginURL(message.frameInfo.request.url),
              isTrustedWatchURL(webView.url),
              let body = message.body as? [String: Any],
              body.count == 2,
              let type = body["type"] as? String,
              type == "fullscreen",
              let value = body["enter"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return
        }
        // frame URL に加え WebKit の securityOrigin も検証する (iframe・認証ドメインを除外)。
        let origin = message.frameInfo.securityOrigin
        guard let frameURL = message.frameInfo.request.url,
              origin.protocol.lowercased() == frameURL.scheme?.lowercased(),
              origin.host.lowercased() == frameURL.host?.lowercased(),
              (origin.port == 0 ? (origin.protocol.lowercased() == "https" ? 443 : 80) : origin.port)
                == (frameURL.port ?? (frameURL.scheme?.lowercased() == "https" ? 443 : 80)) else { return }
        switch type {
        case "fullscreen":
            let enter = value.boolValue
            // バックグラウンド移行前に送られ、遅れて届いた開始通知を採用しない。
            if enter && view.window?.windowScene?.activationState != .foregroundActive {
                resetFullscreen()
                return
            }
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        resetFullscreen()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        setNativeFullscreen(false)
    }

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
