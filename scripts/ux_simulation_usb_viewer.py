"""Loopback USB viewer adapter for pymobiledevice3 11.26.0.

Apply local lifecycle/privacy changes in memory; leave site-packages untouched.
"""
import inspect
from importlib.metadata import version
from pathlib import Path
import runpy
import sys
import textwrap

SUPPORTED_VERSION = "11.26.0"


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError("Upstream viewer changed; refusing an unverified patch")
    return source.replace(old, new, 1)


def patch_viewer(source, lifecycle):
    source = lifecycle + "\nconst gymViewer = createGymNoteViewerLifecycle({document, window, now: () => performance.now()});\n" + source
    anchor = "let _lastFc = -1, _stableSec = 0, _nextPliSec = 0, _nextRestartSec = 0;\nsetInterval(() => {"
    source = replace_once(source, anchor, anchor.replace("setInterval(() => {", """gymViewer.setReset(() => {
    _lastFc = frameCount; _stableSec = 0; _nextPliSec = 0; _nextRestartSec = 0;
    offlineOverlay.classList.add('hidden');
});
setInterval(() => {
    if (!gymViewer.canRecover()) {
        _lastFc = frameCount; _stableSec = 0; _nextPliSec = 0; _nextRestartSec = 0;
        offlineOverlay.classList.add('hidden');
        return;
    }"""))
    source = replace_once(source, "    let decoder = buildDecoder();", "    let streamTerminated = false;\n    let decoder = buildDecoder();")
    source = replace_once(source, "    log('state after configure: ' + decoder.state);", """    log('state after configure: ' + decoder.state);
    gymViewer.setRecover(() => {
        if (streamTerminated) { location.reload(); return; }
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
        catch (error) { streamTerminated = true; throw error; }
        const { value, done } = packet;
        if (done) { streamTerminated = true; log('stream ended'); break; }""")
    source = replace_once(source, "try { if (localStorage.getItem('clipboardSync') === 'true') setClipboardSync(true); } catch (e) {}", "// Clipboard sync is disabled in this local adapter.")
    source += "\nfor (const id of ['clipboard-toggle', 'clipboard-sync', 'clipboard-send', 'clipboard-get', 'clipboard-text', 'sound-toggle']) { const el = document.getElementById(id); if (el) el.disabled = true; }\n"
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
    namespace = dict(vars(module))
    exec(compile(handler, "<gymnote-private-http>", "exec"), namespace)
    cls._handle_http = namespace["_handle_http"]

    async def no_audio(self):
        return

    cls._ensure_audio_stream = no_audio


def main():
    if len(sys.argv) != 1:
        raise SystemExit("No arguments allowed: this adapter always binds to loopback")
    if version("pymobiledevice3") != SUPPORTED_VERSION:
        raise SystemExit("Unsupported pymobiledevice3 version; revalidate the adapter first")
    from pymobiledevice3.remote.core_device import screen_stream
    lifecycle = (Path(__file__).resolve().parent.parent / "simulation/usb/viewer_lifecycle.js").read_text(encoding="utf-8")
    install_patches(screen_stream, lifecycle)
    sys.argv = [sys.argv[0], "developer", "core-device", "display", "serve-web",
                "--bind", "127.0.0.1", "--http-port", "8766", "--no-audio", "--no-motion-idr"]
    runpy.run_module("pymobiledevice3", run_name="__main__")


if __name__ == "__main__":
    main()
