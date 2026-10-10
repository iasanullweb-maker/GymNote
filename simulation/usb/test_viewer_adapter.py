"""No-device regression checks for the privacy gate and source integration."""
import asyncio
import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("adapter", Path(__file__).resolve().parents[2] / "scripts/ux_simulation_usb_viewer.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
from pymobiledevice3.remote.core_device import screen_stream
from viewer_recovery import state_for

lifecycle = Path(__file__).with_name("viewer_lifecycle.js").read_text(encoding="utf-8")
adapter.install_patches(screen_stream, lifecycle)

class Writer:
    def __init__(self): self.data = b""; self.closed = False
    def write(self, data): self.data += data
    async def drain(self): pass
    def close(self): self.closed = True

async def verify():
    # No initialized server or RSD: any device service access would fail this test.
    server = object.__new__(screen_stream.ScreenStreamServer)
    server._refuse_request = lambda headers: None
    for path in ("/clipboard", "/clipboard/events", "/clipboard/image", "/audio.bin"):
        for method in ("GET", "POST"):
            reader = asyncio.StreamReader()
            reader.feed_data(f"{method} {path}?probe=1 HTTP/1.1\r\nHost: 127.0.0.1:8766\r\n\r\n".encode())
            reader.feed_eof()
            writer = Writer()
            await server._handle_http(reader, writer)
            assert writer.data.startswith(b"HTTP/1.1 403"), path
            assert writer.closed
    await server._ensure_audio_stream()
    # Public health response is safe even if the server object holds secrets.
    server._active_service = None
    server._last_good_au_t = 0
    server._rtp_packets_received = 7
    server._subscribers = {}
    server.private_token = "synthetic-secret-must-not-appear"
    state_for(server)
    reader = asyncio.StreamReader()
    reader.feed_data(b"GET /gymnote/health HTTP/1.1\r\nHost: 127.0.0.1:8766\r\n\r\n")
    reader.feed_eof()
    writer = Writer()
    await server._handle_http(reader, writer)
    assert writer.data.startswith(b"HTTP/1.1 200")
    assert b'"packets":7' in writer.data
    assert b"synthetic-secret" not in writer.data
    assert writer.closed
    try:
        adapter.patch_viewer("changed source", lifecycle)
    except RuntimeError:
        pass
    else:
        raise AssertionError("Changed upstream must be rejected")
    assert b"gymViewer.canRecover()" in screen_stream.VIEWER_JS_TEMPLATE
    assert b"gymNoteTouchCoordinates(e" in screen_stream.VIEWER_JS_TEMPLATE
    assert screen_stream.VIEWER_JS_TEMPLATE.count(b"...gymDisplayTouch(") == 3
    assert b"gymTouchSelect" in screen_stream.VIEWER_JS_TEMPLATE
    print("Adapter checks passed (8 denied routes, no audio, safe health counters, changed upstream rejected).")

asyncio.run(verify())
