// 公開 PlayerController の実コードを実行し、アプリ注入との契約を確認する。
// 入力元は docs/baseline.md に記録した固定コミット。動画配信/OS回転は実機で確認する。
const {readFileSync, mkdirSync, writeFileSync} = require('node:fs');
const {resolve} = require('node:path');
const assert = require('node:assert/strict');
const {chromium, webkit} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const source = readFileSync('artifacts/reference/PlayerController-v0.14.1.ts', 'utf8');
const start = source.indexOf('private setupFullscreenHandler(): void {');
assert(start >= 0, 'Pinned PlayerController must expose the inspected fullscreen handler');
const end = source.indexOf('\n    }', start) + 6;
const handler = source.slice(start, end)
    .replace('private setupFullscreenHandler(): void', 'function setupFullscreenHandler()')
    .replaceAll('type?: DPlayerType.FullscreenType', 'type')
    .replaceAll('assert(this.player !== null);', '');
const bridge = readFileSync('KonomiTV-iOS/KonomiTV-iOS/FullscreenBridge.js', 'utf8');
const html = `<html><head><style>
*{box-sizing:border-box} body{margin:0;background:#000;color:white;font-family:sans-serif}
.route-container{height:100vh;border-bottom:21px solid #1e1310;overflow:hidden}
.watch-container{display:flex;width:100%;height:100%}.watch-content{position:relative;flex:1;min-width:0}
.watch-panel{width:310px;flex-shrink:0;background:#39251e}.watch-navigation{width:68px;background:#1e1310}
.watch-header{position:absolute;top:0;background:#1e1310;z-index:2;width:100%;height:60px}
.watch-player{height:100%}video{width:100%;height:100%;object-fit:contain}
.subtitle{position:absolute;bottom:100px;left:20px}.comment{position:absolute;top:100px;left:200px}
.controls{position:absolute;bottom:25px;left:20px;right:20px}button{padding:12px}
</style></head><body><div class="route-container"><main class="watch-container watch-container--panel-display">
<nav class="watch-navigation">Navigation</nav><div class="watch-content"><header class="watch-header">Header</header>
<div class="watch-player"><video playsinline></video><span class="subtitle">Subtitle</span><span class="comment">Comment</span>
<div class="controls"><input type="range"><button id="fullscreen">Fullscreen</button><button>Quality</button></div></div></div>
<aside class="watch-panel">Panel</aside></main></div></body></html>`;

(async () => {
    const browser = await (process.env.BROWSER === 'webkit' ? webkit : chromium).launch({
        ...(process.env.BROWSER_PATH ? {executablePath: process.env.BROWSER_PATH} : {}), headless: true,
    });
    const results = [];
    async function pageFor({url = 'https://konomi.test/videos/watch/1', origin = 'HTTPS://KONOMI.test:443', inject = true, missingEvent = false, locked = false} = {}) {
        const page = await browser.newPage({viewport: {width: 852, height: 393}});
        await page.route('**/*', route => route.fulfill({body: html, contentType: 'text/html'}));
        await page.addInitScript(() => {
            window.messages = [];
            window.webkit = {messageHandlers: {konomiNative: {postMessage: m => messages.push(m)}}};
            // iPhone のページ全体Fullscreen API不在を再現する。
            Object.defineProperty(HTMLElement.prototype, 'requestFullscreen', {value: undefined, writable: true, configurable: true});
            Object.defineProperty(HTMLElement.prototype, 'webkitRequestFullscreen', {value: undefined, writable: true, configurable: true});
            window.originalPiP = HTMLVideoElement.prototype.requestPictureInPicture;
        });
        if (missingEvent) await page.addInitScript(() => {
            Object.defineProperty(HTMLElement.prototype, 'onfullscreenchange', {value: undefined, writable: true, configurable: true});
        });
        if (locked) await page.addInitScript(() => {
            Object.defineProperty(document, 'fullscreenElement', {get: () => null, configurable: false});
            window.mutations = 0;
            new MutationObserver(() => {window.mutations++;}).observe(document, {childList: true, subtree: true});
        });
        if (inject) await page.addInitScript(`${bridge}(${JSON.stringify(origin)});`);
        await page.goto(url);
        await page.evaluate('(() => {' + handler + `
            window.store = {is_fullscreen: false}; window.usePlayerStore = () => store;
            window.installController = () => {
                window.controller = {player: {fullScreen: {}, notice: () => {window.notice = true;}}};
                setupFullscreenHandler.call(controller);
                document.querySelector('#fullscreen').onclick = () => controller.player.fullScreen.request();
            }; installController(); })();`);
        return page;
    }
    async function check(name, fn) { await fn(); results.push(name); console.log('PASS ' + name); }
    try {
        await check('Unmodified client reproduces unsupported notice', async () => {
            const p = await pageFor({inject: false}); await p.click('#fullscreen');
            assert.equal(await p.evaluate(() => window.notice), true); await p.close();
        });
        for (const missingEvent of [false, true]) await check(`Existing controller enter/exit, event absent=${missingEvent}`, async () => {
            const p = await pageFor({missingEvent});
            const video = await p.locator('video').elementHandle();
            await p.click('#fullscreen');
            assert.equal(await p.evaluate(() => store.is_fullscreen && document.fullscreenElement === document.body), true);
            assert.equal(await p.locator('.watch-header').isVisible(), false);
            assert.equal(await p.locator('.watch-panel').isVisible(), false);
            assert.equal(await p.locator('.subtitle').isVisible(), true);
            assert.equal(await p.locator('.comment').isVisible(), true);
            const bounds = await p.locator('.watch-player').boundingBox(); assert.equal(bounds.width, 852); assert.equal(bounds.height, 393);
            assert.equal(await p.evaluate(() => HTMLVideoElement.prototype.requestPictureInPicture === originalPiP), true);
            assert.equal(await video.evaluate(v => v === document.querySelector('video')), true);
            mkdirSync('artifacts/verification', {recursive: true});
            await p.screenshot({path: `artifacts/verification/fixture-fullscreen-${missingEvent}.png`});
            await p.click('#fullscreen');
            assert.equal(await p.evaluate(() => store.is_fullscreen), false);
            assert.equal(await p.locator('.watch-panel').isVisible(), true);
            assert.deepEqual(await p.evaluate(() => messages.map(m => m.enter)), [true, false]);
            await p.close();
        });
        await check('Repeated toggles, quality replacement, controller recreation and native reset', async () => {
            const p = await pageFor();
            for (let i = 0; i < 10; i++) await p.click('#fullscreen');
            assert.equal(await p.evaluate(() => messages.length), 10);
            await p.click('#fullscreen');
            await p.evaluate(() => {document.querySelector('video').replaceWith(document.createElement('video')); store.is_fullscreen = false; installController();});
            await p.waitForFunction(() => store.is_fullscreen);
            await p.evaluate(() => document.dispatchEvent(new Event('konomi-native-fullscreen-reset')));
            assert.equal(await p.evaluate(() => store.is_fullscreen), false);
            assert.equal(await p.evaluate(() => messages.length), 11);
            await p.close();
        });
        await check('SPA watch departure restores APIs and reentry reinstalls', async () => {
            const p = await pageFor(); await p.click('#fullscreen');
            await p.evaluate(() => {history.pushState({}, '', '/videos'); document.querySelector('.watch-container').remove();});
            await p.waitForFunction(() => !Object.hasOwn(document.body, 'requestFullscreen'));
            assert.equal(await p.evaluate(() => messages.at(-1).enter), false);
            assert.equal(await p.evaluate(() => document.querySelector('style:last-child').textContent.includes('konomi-native-fullscreen')), false);
            await p.evaluate(() => {history.pushState({}, '', '/tv/watch/gr011'); const w = document.createElement('main'); w.className = 'watch-container'; document.body.append(w);});
            await p.waitForFunction(() => typeof document.body.requestFullscreen === 'function');
            await p.close();
        });
        for (const url of ['https://access.test/videos/watch/1', 'https://konomi.test/cdn-cgi/access/login', 'https://konomi.test/login', 'https://konomi.test:8443/videos/watch/1']) {
            await check(`Excluded page: ${url}`, async () => {
                const p = await pageFor({url});
                assert.equal(await p.evaluate(() => Object.hasOwn(document.body, 'requestFullscreen')), false);
                assert.equal(await p.evaluate(() => messages.length), 0); await p.close();
            });
        }
        await check('Background/pagehide exits and same node remains', async () => {
            const p = await pageFor(); await p.click('#fullscreen');
            await p.evaluate(() => {Object.defineProperty(document, 'hidden', {value: true, configurable: true}); document.dispatchEvent(new Event('visibilitychange'));});
            assert.equal(await p.evaluate(() => store.is_fullscreen), false);
            await p.click('#fullscreen'); await p.evaluate(() => window.dispatchEvent(new Event('pagehide')));
            assert.equal(await p.evaluate(() => store.is_fullscreen), false); await p.close();
        });
        await check('Nonconfigurable API fails safely without observer loop', async () => {
            const p = await pageFor({locked: true});
            const count = await p.evaluate(() => mutations);
            await p.evaluate(() => new Promise(resolve => setTimeout(resolve, 50)));
            assert.equal(await p.evaluate(() => mutations), count);
            assert.equal(await p.evaluate(() => Object.hasOwn(document.body, 'requestFullscreen')), false);
            assert.equal(await p.evaluate(() => messages.length), 0);
            await p.close();
        });
        await check('Foreground PiP event exits layout without replacing video APIs', async () => {
            const p = await pageFor(); await p.click('#fullscreen');
            await p.evaluate(() => document.querySelector('video').dispatchEvent(new Event('enterpictureinpicture')));
            assert.equal(await p.evaluate(() => store.is_fullscreen), false);
            assert.equal(await p.evaluate(() => HTMLVideoElement.prototype.requestPictureInPicture === originalPiP), true);
            await p.click('#fullscreen');
            await p.evaluate(() => {
                const v = document.querySelector('video');
                // WebKitの実プロパティは読み取り専用なので、イベント再現用のown getterを置く。
                Object.defineProperty(v, 'webkitPresentationMode', {get: () => 'picture-in-picture', configurable: true});
                if (v.webkitPresentationMode !== 'picture-in-picture') throw new Error('PiP fixture not initialized');
                v.dispatchEvent(new Event('webkitpresentationmodechanged'));
            });
            assert.equal(await p.evaluate(() => store.is_fullscreen), false);
            await p.close();
        });
        writeFileSync(resolve('artifacts/verification/browser-results.json'), JSON.stringify({browser: process.env.BROWSER || 'chromium', passed: results}, null, 2));
    } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
