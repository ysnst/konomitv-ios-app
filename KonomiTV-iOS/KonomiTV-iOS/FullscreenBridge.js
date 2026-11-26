// このファイルは WKUserScript の関数本体として使う。信頼するオリジンは Swift から渡す。
(function installFullscreenBridge(trustedOrigin) {
    'use strict';
    if (window.top !== window || location.origin !== new URL(trustedOrigin).origin) return;

    let installed = null;
    let failedWatch = null;
    let active = false;
    const isWatch = () => /^\/(tv|videos)\/watch\/[^/]+\/?$/.test(location.pathname);
    const post = (enter) => window.webkit.messageHandlers.konomiNative.postMessage({type: 'fullscreen', enter});

    function emit() {
        // 公開 PlayerController の既存ハンドラーに is_fullscreen を更新させる。
        // Vue/Pinia の内部オブジェクトや動画の再生状態には触れない。
        for (const name of ['fullscreenchange', 'webkitfullscreenchange']) {
            document.body.dispatchEvent(new Event(name, {bubbles: true}));
        }
        window.dispatchEvent(new Event('resize'));
    }

    function setActive(enter, notify = true) {
        if (active === enter) return;
        active = enter;
        document.documentElement.classList.toggle('konomi-native-fullscreen', enter);
        emit();
        if (notify) post(enter);
    }

    function uninstall() {
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
                .konomi-native-fullscreen .watch-container { width: 100% !important; transition: none !important; }
                .konomi-native-fullscreen .watch-content { width: 100% !important; flex: 1 1 auto; }
                .konomi-native-fullscreen .watch-header,
                .konomi-native-fullscreen .watch-navigation,
                .konomi-native-fullscreen .watch-panel { display: none !important; }
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
    document.addEventListener('konomi-native-fullscreen-reset', () => setActive(false, false));
    // PiP APIそのものは変更せず、前景のまま小窓へ移る場合も通常レイアウトへ戻す。
    document.addEventListener('enterpictureinpicture', () => setActive(false), true);
    document.addEventListener('webkitpresentationmodechanged', (event) => {
        if (event.target.webkitPresentationMode === 'picture-in-picture') setActive(false);
    }, true);
    // バックグラウンド/PiP 中は動画に触れず表示だけ通常へ戻す。
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) setActive(false);
        else { refresh(); if (installed) emit(); }
    });
    refresh();
})
