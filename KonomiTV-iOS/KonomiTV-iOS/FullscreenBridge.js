// このファイルは WKUserScript の関数本体として使う。信頼するオリジンは Swift から渡す。
(function installFullscreenBridge(trustedOrigin) {
    'use strict';
    if (window.top !== window || location.origin !== new URL(trustedOrigin).origin) return;

    let installed = null;
    let failedWatch = null;
    let active = false;
    const isWatch = () => /^\/(tv|videos)\/watch\/[^/]+\/?$/.test(location.pathname);
    const post = (enter) => window.webkit.messageHandlers.konomiNative.postMessage({type: 'fullscreen', enter});

    // 停止の発生順序を観測するだけで、play/pause/PiP/配信ソースを操作しない。
    const mediaEvents = ['play', 'playing', 'pause', 'waiting', 'stalled', 'ratechange', 'error', 'emptied',
        'loadedmetadata', 'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged'];
    function recordMedia(event) {
        if (!isWatch()) return;
        if (mediaEvents.includes(event.type) && !(event.target instanceof HTMLVideoElement)) return;
        const video = event.target instanceof HTMLVideoElement ? event.target : document.querySelector('.watch-player video');
        if (!video || !video.isConnected || !video.closest('.watch-player')) return;
        const finite = value => Number.isFinite(value) && value >= 0 ? value : 0;
        let bufferAhead = 0;
        try {
            for (let index = 0; index < video.buffered.length; index++) {
                if (video.buffered.start(index) <= video.currentTime && video.currentTime <= video.buffered.end(index)) {
                    bufferAhead = video.buffered.end(index) - video.currentTime;
                    break;
                }
            }
        } catch { /* バッファ入替中の取得失敗は0として記録する。 */ }
        const known = (value, values) => values.includes(value) ? value : 'unknown';
        const audio = navigator.audioSession;
        window.webkit.messageHandlers.konomiNative.postMessage({type: 'mediaDiagnostic', event: event.type, state: {
            time: Date.now(), paused: video.paused, ended: video.ended, hidden: document.hidden,
            readyState: video.readyState, networkState: video.networkState, position: finite(video.currentTime),
            rate: finite(video.playbackRate), bufferAhead: finite(bufferAhead), error: video.error?.code ?? 0,
            pip: document.pictureInPictureElement === video ? 'picture-in-picture' :
                known(video.webkitPresentationMode ?? 'inline', ['inline', 'picture-in-picture', 'fullscreen']),
            audioState: known(audio?.state, ['active', 'inactive', 'interrupted']),
            audioType: known(audio?.type, ['auto', 'playback', 'transient', 'transient-solo', 'ambient', 'play-and-record'])
        }});
    }
    for (const event of mediaEvents) document.addEventListener(event, recordMedia, true);
    document.addEventListener('visibilitychange', recordMedia);
    window.addEventListener('pagehide', recordMedia);
    document.addEventListener('konomi-diagnostics-snapshot', () => recordMedia({type: 'snapshot', target: document}));

    // 録画の背景入りでWebKitがinline動画を止めた場合だけ、同じ動画で音声の継続を1回試す。
    // 非アクティブ化だけでは実行しないため、Control Centerの操作と背景移行を区別する。
    // ライブ不調の報告と背景play直後のdecodeエラー反復を受け対象外。既存の手動PiPを使う。
    const isRecordedWatch = () => /^\/videos\/watch\/[^/]+\/?$/.test(location.pathname);
    let backgroundAudio = null;
    let isBackground = false;
    const inPiP = video => document.pictureInPictureElement === video || video.webkitPresentationMode === 'picture-in-picture';
    const clearBackgroundAudio = () => { backgroundAudio = null; isBackground = false; };
    function resumeBackgroundAudio() {
        const saved = backgroundAudio;
        // 記憶後にSPAでライブへ遷移した場合も、旧候補から強制再開させない。
        if (!isRecordedWatch()) { clearBackgroundAudio(); return; }
        if (!saved || saved.attempted || !isBackground || !document.hidden) return;
        const video = saved.video;
        if (!video.isConnected || video !== document.querySelector('.watch-player video') || video.currentSrc !== saved.source ||
            video.ended || video.error || video.muted || video.volume === 0 || inPiP(video) ||
            navigator.audioSession?.state === 'interrupted' || performance.now() - saved.time > 2500) {
            clearBackgroundAudio();
            return;
        }
        // hiddenと背景通知が揃った最初の観測だけを使う。既に継続中なら候補を捨て、
        // 後からロック画面等で押された一時停止を背景停止と誤認しない。
        if (!video.paused) { clearBackgroundAudio(); return; }
        // 再生が拒否された場合も再試行しない。以後の一時停止操作を上書きしないため。
        saved.attempted = true;
        recordMedia({type: 'background-audio-attempt', target: video});
        try {
            Promise.resolve(video.play()).then(() => {
                if (backgroundAudio === saved) recordMedia({type: 'background-audio-started', target: video});
            }, () => {
                if (backgroundAudio === saved) recordMedia({type: 'background-audio-rejected', target: video});
            });
        } catch {
            recordMedia({type: 'background-audio-rejected', target: video});
        }
    }
    document.addEventListener('konomi-background-audio', event => {
        if (event.detail === 'capture') {
            clearBackgroundAudio();
            const video = isRecordedWatch() && document.querySelector('.watch-player video');
            if (video && video.readyState >= 2 && !video.paused && !video.ended && !video.error && !video.muted && video.volume > 0 && !inPiP(video)) {
                backgroundAudio = {video, source: video.currentSrc, time: performance.now(), attempted: false};
            }
        } else if (event.detail === 'background') {
            isBackground = true;
            resumeBackgroundAudio();
        } else if (event.detail === 'foreground') clearBackgroundAudio();
    });
    document.addEventListener('pause', event => {
        if (event.target !== backgroundAudio?.video) return;
        // 背景入りの通知前のpauseは利用者/ページ側の停止として尊重する。
        if (!isBackground) backgroundAudio = null;
    }, true);
    document.addEventListener('visibilitychange', resumeBackgroundAudio);
    window.addEventListener('pagehide', clearBackgroundAudio);

    function emit() {
        // 公開 PlayerController の既存ハンドラーに is_fullscreen を更新させる。
        // Vue/Pinia の内部オブジェクトや動画の再生状態には触れない。
        for (const name of ['fullscreenchange', 'webkitfullscreenchange']) {
            document.body.dispatchEvent(new Event(name, {bubbles: true}));
        }
        window.dispatchEvent(new Event('resize'));
    }

    function setActive(enter) {
        if (active === enter) return;
        active = enter;
        document.documentElement.classList.toggle('konomi-native-fullscreen', enter);
        emit();
        post(enter);
    }

    function uninstall() {
        clearBackgroundAudio();
        if (!installed) return;
        setActive(false);
        installed.removeListener?.();
        installed.removeStyle?.();
        // SPA で認証画面・一覧へ移ったら API を元に戻す。
        for (const [object, key, descriptor] of installed.saved.reverse()) {
            if (descriptor) Object.defineProperty(object, key, descriptor);
            else delete object[key];
        }
        installed = null;
    }

    function refresh() {
        const watch = isWatch() && document.querySelector('.watch-container');
        if (!watch) { uninstall(); return; }
        // API が書き換え不能な同じ画面へ再試行すると style の追加/削除で監視が反復する。
        if (watch === failedWatch) return;
        if (installed) {
            if (installed.watch !== watch) uninstall();
            else {
                // プレイヤー再生成でイベントハンドラーだけ更新された場合にも状態を渡す。
                if (active && installed.handler !== document.body.onfullscreenchange) emit();
                installed.handler = document.body.onfullscreenchange;
                return;
            }
        }
        // プレイヤー以外のページには API の変更を適用しない。
        const body = document.body;
        if (!body) return;
        const saved = [];
        const define = (object, key, descriptor) => {
            saved.push([object, key, Object.getOwnPropertyDescriptor(object, key)]);
            Object.defineProperty(object, key, {configurable: true, ...descriptor});
        };
        installed = {watch, saved};
        try {
            // WebView を端まで広げても残るページの安全領域とナビを、全画面中だけ取り除く。
            // 字幕・コメント・DPlayer 操作部品は既存 DOM のまま維持する。
            const style = document.createElement('style');
            style.textContent = `
                .konomi-native-fullscreen .route-container { border: 0 !important; }
                .konomi-native-fullscreen .watch-header,
                .konomi-native-fullscreen .watch-navigation { display: none !important; }
            `;
            document.head.append(style);
            installed.removeStyle = () => style.remove();
            const request = function () {
                if (this !== document.body || !isWatch()) return Promise.reject(new Error('Unsupported fullscreen target'));
                setActive(true);
                return Promise.resolve();
            };
            const exit = () => { setActive(false); return Promise.resolve(); };
            // body だけを置き換えるため、video.webkitEnterFullscreen や PiP は変わらない。
            define(body, 'requestFullscreen', {value: request, writable: true});
            define(body, 'webkitRequestFullscreen', {value: request, writable: true});
            define(document, 'exitFullscreen', {value: exit, writable: true});
            define(document, 'webkitExitFullscreen', {value: exit, writable: true});
            for (const key of ['fullscreenElement', 'webkitFullscreenElement']) {
                define(document, key, {get: () => active ? body : null});
            }
            // iPhone で未定義の場合も、PlayerController が標準イベント経路を選べるようにする。
            // 未実装イベントの on... は dispatchEvent に連動しないため明示的に呼ぶ。
            if (body.onfullscreenchange === undefined) {
                define(body, 'onfullscreenchange', {value: null, writable: true});
                const handler = (event) => body.onfullscreenchange?.(event);
                body.addEventListener('fullscreenchange', handler);
                installed.removeListener = () => body.removeEventListener('fullscreenchange', handler);
            }
        } catch {
            // API が書き換え不能なクライアントでは中途半端な状態を残さない。
            failedWatch = watch;
            uninstall();
        }
    }

    // DOM の入れ替えに追随し、画質変更で video だけが変わる場合は全画面を維持する。
    new MutationObserver(refresh).observe(document, {childList: true, subtree: true});
    window.addEventListener('popstate', refresh);
    window.addEventListener('pagehide', () => { setActive(false); });
    // ネイティブからのresetも応答する。非同期resetと次のenterが交差しても最終状態を揃える。
    document.addEventListener('konomi-native-fullscreen-reset', () => setActive(false));
    // PiP/背景移行では全画面状態を保つ。移行中の縦回転や復帰時の疑似resizeを避け、
    // WebKitによる動画の表示先変更へ介入しない。明示解除・ページ離脱時だけ状態を戻す。
    refresh();
})
