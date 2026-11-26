import AVFoundation
import UIKit

/// アプリ全体の土台。
/// 役割は2つだけ: (1) 音声まわりの初期設定 (PiP とバックグラウンド再生のため)
/// (2) 全画面中に ViewController から受けた「向きの固定」を、アプリ全体の許可向きへ反映すること。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// 現在許可する画面の向き。ふだんは縦・横の両方、全画面中は横だけ。
    /// ViewController が全画面の開始・終了に合わせて書き換える。
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    private var diagnosticObservers: [NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        observeAudioDiagnostics()
        activateAudioSession()
        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // MARK: - 向きの制御

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    // MARK: - 音声セッション

    /// PiP (映像を小窓に出したまま他のアプリを使う) とバックグラウンド再生のため、
    /// 音声セッションを「再生」カテゴリにしておく。
    /// Apple の案内でも、WKWebView の映像を PiP 対象にするには
    /// このカテゴリと、Info.plist のバックグラウンドモード (audio) が前提になる。
    static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        PlaybackDiagnostics.record("native.audioConfigureBegin", ["category": session.category.rawValue, "mode": session.mode.rawValue])
        var stage = "category"
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            PlaybackDiagnostics.record("native.audioCategorySet", ["category": session.category.rawValue, "mode": session.mode.rawValue])
            stage = "active"
            try session.setActive(true)
            PlaybackDiagnostics.record("native.audioConfigureEnd", ["category": session.category.rawValue, "mode": session.mode.rawValue])
        } catch {
            PlaybackDiagnostics.record("native.audioConfigureError", ["code": (error as NSError).code, "stage": stage])
            // 音が出ない等の致命傷ではないので、起動は止めずに記録だけ残す
            print("[KonomiTV-iOS] Failed to activate audio session: \(error)")
        }
    }

    private func activateAudioSession() {
        AppDelegate.activateAudioSession()
    }

    /// 通知を観測するだけで、割り込み時の再生/音声セッション状態を変更しない。
    private func observeAudioDiagnostics() {
        let center = NotificationCenter.default
        diagnosticObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
            let info = notification.userInfo ?? [:]
            PlaybackDiagnostics.record("native.audioInterruption", [
                "type": (info[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.intValue ?? -1,
                "options": (info[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.intValue ?? 0,
                "reason": (info[AVAudioSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
            ])
        })
        diagnosticObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { notification in
            PlaybackDiagnostics.record("native.audioRouteChange", ["reason": (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? -1])
        })
        diagnosticObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            PlaybackDiagnostics.record("native.mediaServicesReset")
        })
    }
}
