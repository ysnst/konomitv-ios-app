import AVFoundation
import UIKit
import WebKit

/// KonomiTV を WKWebView で開く、アプリの唯一の画面。
///
/// 担うのは次の3点だけ (それ以外は KonomiTV 側の作りに任せる):
/// 1. WebView の設定 (インライン再生・PiP 許可・User-Agent の印)
/// 2. Web 側からの全画面の通知を受けて、ステータスバーを隠し、OS ごと横向きにすること
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

    /// ネイティブ全画面中かどうか。ステータスバーとホームインジケーターの表示が連動する。
    private var isNativeFullscreen = false {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    /// 最後に読み込んだ URL。設定で URL が変わっていたら読み直すために保持する。
    private var lastLoadedURLString: String?

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
        view.backgroundColor = .black

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
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        self.webView = webView

        loadHome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 設定アプリで URL を変えて戻ってきたら、新しい URL を開き直す
        if let current = Self.homeURLString(), current != lastLoadedURLString, lastLoadedURLString != nil {
            loadHome()
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeName)
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
        isNativeFullscreen = enter
        if enter {
            AppDelegate.orientationLock = .landscape
            requestLandscape()
        } else {
            // 終了時は固定を外すだけにする。広い向きの組をそのまま OS に要求すると
            // 断られるため、許可向きの再評価だけを促し、実際の回転は端末の向きに任せる。
            AppDelegate.orientationLock = .allButUpsideDown
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    /// ウィンドウシーン自体の向き切り替えを OS に頼み、横向きにする。
    /// CSS で画面だけを回す Web 版と違い、こちらは OS の向きが変わるので、
    /// スクリーンショットも横向きのまま撮れる。
    private func requestLandscape() {
        if #available(iOS 16.0, *) {
            guard let scene = view.window?.windowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                print("[KonomiTV-iOS] Geometry update rejected: \(error)")
            }
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            // iOS 15 以前向けの従来手法 (対象 OS は 16 以降だが、保険として残す)
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
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
