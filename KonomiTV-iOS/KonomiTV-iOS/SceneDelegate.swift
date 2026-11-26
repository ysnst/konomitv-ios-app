import UIKit

/// 画面 (ウィンドウ) の生成だけを行う。
/// 中身はすべて ViewController 側に寄せ、このファイルは薄く保つ。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ViewController()
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        PlaybackDiagnostics.record("native.sceneDidBecomeActive")
        // 実機ログでは復帰時のsetActive中〜直後にPiP動画が停止していた。
        // WebKitが再生中の音声セッションをアプリ側から再取得せず、観測だけ行う。
        (window?.rootViewController as? ViewController)?.recordPlaybackSnapshot()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        PlaybackDiagnostics.record("native.sceneWillResignActive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        PlaybackDiagnostics.record("native.sceneDidEnterBackground")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        PlaybackDiagnostics.record("native.sceneWillEnterForeground")
    }

}
