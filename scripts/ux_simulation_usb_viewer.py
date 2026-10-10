"""Loopback USB viewer adapter for pymobiledevice3 11.26.0.

Apply local lifecycle/privacy changes in memory; leave site-packages untouched.
"""
import inspect
import os
import asyncio
from importlib.metadata import version
from pathlib import Path
import runpy
import sys
import textwrap

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "simulation/usb"))
from viewer_recovery import FRESH_TUNNEL_EXIT, FreshTunnelRequired, install_recovery, supervise

SUPPORTED_VERSION = "11.26.0"


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError("Upstream viewer changed; refusing an unverified patch")
    return source.replace(old, new, 1)


def patch_viewer(source, lifecycle):
    coordinates = (Path(__file__).resolve().parent.parent / "simulation/usb/viewer_coordinates.js").read_text(encoding="utf-8")
    if source.count("function touchCoords(e) {") != 1 or source.count("\nasync function postJson") != 1:
        raise RuntimeError("Upstream touch mapping changed; refusing an unverified patch")
    start = source.index("function touchCoords(e) {")
    end = source.index("\nasync function postJson", start)
    original = source[start:end]
    source = replace_once(source, original, """let gymTouchMode = 'auto';
function touchCoords(e) {
    const rect = canvas.getBoundingClientRect();
    return gymNoteTouchCoordinates(e, {
        left: rect.left, top: rect.top, width: rect.width, height: rect.height,
        canvasWidth: canvas.width, canvasHeight: canvas.height, visualRotation,
    }, gymTouchMode);
}
""")
    source = coordinates + "\n" + source
    source = replace_once(source, "async function swipe(direction) {", """function gymDisplayTouch(x, y) {
    const rect = canvas.getBoundingClientRect();
    return touchCoords({clientX: rect.left + x / 65535 * rect.width,
                        clientY: rect.top + y / 65535 * rect.height});
}
async function swipe(direction) {""")
    for kind, x in [('contact', 'xStart'), ('contact', 'x'), ('release', 'xEnd')]:
        x_field = 'x' if x == 'x' else 'x: ' + x
        source = replace_once(source, "{type: '" + kind + "', " + x_field + ", y: yMid}",
                              "{type: '" + kind + "', ...gymDisplayTouch(" + x + ", yMid)}")
    source = lifecycle + "\nconst gymViewer = createGymNoteViewerLifecycle({document, window, now: () => performance.now()});\n" + source
    anchor = "let _lastFc = -1, _stableSec = 0, _nextPliSec = 0, _nextRestartSec = 0;\nsetInterval(() => {"
    source = replace_once(source, anchor, anchor.replace("setInterval(() => {", """gymViewer.setReset(() => {
    _lastFc = frameCount; _stableSec = 0; _nextPliSec = 0; _nextRestartSec = 0;
    offlineOverlay.classList.add('hidden');
});
setInterval(() => {
    if (!gymViewer.canRecover() || (gymServerHealth?.video_idle && performance.now() - gymHealthUpdated < 5000)) {
        _lastFc = frameCount; _stableSec = 0; _nextPliSec = 0; _nextRestartSec = 0;
        offlineOverlay.classList.add('hidden');
        return;
    }"""))
    source = replace_once(source, "    let decoder = buildDecoder();", "    let streamTerminated = false;\n    let decoder = buildDecoder();")
    source = replace_once(source, "    log('state after configure: ' + decoder.state);", """    log('state after configure: ' + decoder.state);
    gymViewer.setRecover(() => {
        if (streamTerminated) { gymReconnectViewer(); return; }
        if (decoder.state !== 'configured' || needsResync) {
            try { decoder.close(); } catch (_) {}
            decoder = buildDecoder();
            decoder.configure(decoderConfig);
            needsResync = true;
        }
        if (pendingFrame && !rafScheduled) {
            rafScheduled = true; requestAnimationFrame(drawPending);
        }
        fetch('/pli', {method: 'POST', cache: 'no-store'})
            .catch(err => log('foreground recovery: ' + err.message));
    });""")
    source = replace_once(source, "            needsResync = true;\n            // Bootstrap-failure", "            needsResync = true;\n            if (!gymViewer.isActive()) return;\n            // Bootstrap-failure")
    source = replace_once(source, "        const { value, done } = await reader.read();\n        if (done) { log('stream ended'); break; }", """        let packet;
        try { packet = await reader.read(); }
        catch (error) { streamTerminated = true; gymReconnectViewer(); throw error; }
        const { value, done } = packet;
        if (done) { streamTerminated = true; gymReconnectViewer(); log('stream ended'); break; }
        gymBrowserCounters.bytes += value.length;""")
    source = replace_once(source, "            const type = buf[4];", "            gymBrowserCounters.messages++;\n            const type = buf[4];")
    source = replace_once(source, "        drawFrame(f);", "        drawFrame(f); gymBrowserCounters.drawn++;")
    source = """const gymBrowserCounters = {bytes: 0, messages: 0, drawn: 0};
let gymReconnectPending = false;
const gymStartedAt = performance.now();
let gymServerHealth = null;
let gymHealthUpdated = 0;
function gymReconnectViewer() {
    if (gymReconnectPending) return;
    gymReconnectPending = true;
    let remaining = Math.min(3, Number(sessionStorage.getItem('gymReconnectBudget') ?? '3'));
    if (!Number.isFinite(remaining) || remaining <= 0) {
        log('USB reconnect limit reached; reload manually after checking the connection.');
        return;
    }
    sessionStorage.setItem('gymReconnectBudget', String(remaining - 1));
    // Let orderly server cleanup and fresh tunnel establishment finish.
    setTimeout(() => location.reload(), {3: 5000, 2: 15000, 1: 30000}[remaining]);
}
""" + source
    source = replace_once(source, "            frameCount++;", """            frameCount++;
            if (frameCount >= 300 && performance.now() - gymStartedAt >= 60000)
                sessionStorage.setItem('gymReconnectBudget', '3');""")
    source = replace_once(source, "run().catch(e => log('fatal: ' + e.message));", "run().catch(e => { log('fatal: ' + e.message); gymReconnectViewer(); });")
    source += """
const gymCounterPanel = document.createElement('pre');
gymCounterPanel.setAttribute('aria-label', 'USB 연결 진단 카운터');
document.body.append(gymCounterPanel);
setInterval(async () => {
    try {
        const response = await fetch('/gymnote/health', {cache: 'no-store'});
        if (!response.ok) return;
        const health = await response.json();
        gymServerHealth = health;
        gymHealthUpdated = performance.now();
        gymCounterPanel.textContent = JSON.stringify({server: health, browser: {
            ...gymBrowserCounters, decoded: frameCount, visible: document.visibilityState === 'visible',
        }}, null, 2);
    } catch (_) { /* A worker restart temporarily closes the listener. */ }
}, 2000);
"""
    source = replace_once(source, "try { if (localStorage.getItem('clipboardSync') === 'true') setClipboardSync(true); } catch (e) {}", "// Clipboard sync is disabled in this local adapter.")
    source += "\nfor (const id of ['clipboard-toggle', 'clipboard-sync', 'clipboard-send', 'clipboard-get', 'clipboard-text', 'sound-toggle']) { const el = document.getElementById(id); if (el) el.disabled = true; }\n"
    source += """
const gymTouchLabel = document.createElement('label');
gymTouchLabel.textContent = '터치 좌표: ';
gymTouchLabel.style.cssText = 'display:block;padding:8px;text-align:center;color:#fff;background:#222';
const gymTouchSelect = document.createElement('select');
for (const [value, title] of [['auto','자동 (확인된 가로 방향 270°)'], ['0','보정 없음 / 세로'], ['90','반대 가로 90°'], ['270','가로 270° (확인됨)'], ['180','뒤집힌 세로 180°']]) {
    const option = document.createElement('option'); option.value = value; option.textContent = title;
    gymTouchSelect.append(option);
}
gymTouchSelect.setAttribute('aria-label', '터치 좌표 보정');
gymTouchSelect.addEventListener('change', () => { releaseActive(); gymTouchMode = gymTouchSelect.value; });
gymTouchLabel.append(gymTouchSelect); document.body.prepend(gymTouchLabel);
"""
    return source


def install_patches(module, lifecycle):
    module.VIEWER_JS_TEMPLATE = patch_viewer(module.VIEWER_JS_TEMPLATE.decode(), lifecycle).encode()
    cls = module.ScreenStreamServer
    handler = textwrap.dedent(inspect.getsource(cls._handle_http))
    needle = '        path = target.split("?", 1)[0]\n'
    guard = '''        if path.startswith("/clipboard") or path == "/audio.bin":
            writer.write(b"HTTP/1.1 403 Disabled\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n")
            await writer.drain()
            writer.close()
            return
'''
    handler = replace_once(handler, needle, needle + guard)
    health = '''        if path == "/gymnote/health":
            await self._gym_health_http(writer)
            return
        if path == "/gymnote/stop" and method == "POST":
            stop = getattr(self, "_gym_stop_event", None)
            if stop is not None:
                stop.set()
            writer.write(b"HTTP/1.1 202 Accepted\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n")
            await writer.drain()
            writer.close()
            return
        if path == "/gymnote/observe-idle" and method == "POST":
            self._gym_recovery.watchdog_hold_until = asyncio.get_running_loop().time() + 90
            writer.write(b"HTTP/1.1 202 Accepted\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n")
            await writer.drain()
            writer.close()
            return
'''
    handler = replace_once(handler, needle, needle + health)
    handler = replace_once(handler, "self._hid_queue.put_nowait((path, body))",
                           "self._hid_queue.put_nowait((path, body)); self._gym_recovery.last_input_t = asyncio.get_running_loop().time()")
    # Only the video subscriber loop has this exact exit branch.
    anchor = '''            await writer.drain()
    except (ConnectionResetError, BrokenPipeError, asyncio.CancelledError):
        pass
    finally:
        self._subscribers.pop(queue, None)'''
    handler = replace_once(handler, anchor, anchor.replace("    except", "            self._gym_recovery.counters['http_messages'] += 1\n    except", 1))
    namespace = dict(vars(module))
    exec(compile(handler, "<gymnote-private-http>", "exec"), namespace)
    cls._handle_http = namespace["_handle_http"]

    async def no_audio(self):
        return

    cls._ensure_audio_stream = no_audio
    install_recovery(module, replace_once)


def main():
    worker = sys.argv[1:] == ["--worker"]
    if len(sys.argv) != 1 and not worker:
        raise SystemExit("No arguments allowed: this adapter always binds to loopback")
    if version("pymobiledevice3") != SUPPORTED_VERSION:
        raise SystemExit("Unsupported pymobiledevice3 version; revalidate the adapter first")
    if not worker:
        # Pin every new worker to the same USB device without logging its ID.
        from pymobiledevice3.usbmux import list_devices
        from pymobiledevice3.cli.cli_common import UDID_ENV_VAR
        devices = [d for d in asyncio.run(list_devices()) if d.is_usb]
        target = os.environ.get(UDID_ENV_VAR)
        if target is None:
            if len(devices) != 1:
                raise SystemExit("Connect exactly one USB iPad, or select the device with PYMOBILEDEVICE3_UDID.")
            os.environ[UDID_ENV_VAR] = devices[0].serial
        raise SystemExit(supervise([sys.executable, str(Path(__file__).resolve()), "--worker"]))
    from pymobiledevice3.remote.core_device import screen_stream
    lifecycle = (Path(__file__).resolve().parent.parent / "simulation/usb/viewer_lifecycle.js").read_text(encoding="utf-8")
    install_patches(screen_stream, lifecycle)
    sys.argv = [sys.argv[0], "developer", "core-device", "display", "serve-web",
                "--bind", "127.0.0.1", "--http-port", "8766", "--no-audio", "--no-motion-idr"]
    try:
        runpy.run_module("pymobiledevice3", run_name="__main__")
    except FreshTunnelRequired:
        raise SystemExit(FRESH_TUNNEL_EXIT) from None


if __name__ == "__main__":
    main()
