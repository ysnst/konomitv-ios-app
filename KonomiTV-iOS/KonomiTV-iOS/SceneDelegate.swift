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
        // 設定アプリで開く URL を変えて戻ってきた場合などに備え、音声セッションを有効に戻す。
        // URL の再読み込み自体は ViewController.viewWillAppear で判定する。
        AppDelegate.activateAudioSession()
    }

}
