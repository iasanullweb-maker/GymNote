"""No-device checks for real failure paths, cancellation and retry bounds."""
import asyncio
from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import viewer_recovery as recovery


def server():
    return SimpleNamespace(_active_service=None, _stream_dirty=True)


class RecoveryChecks(unittest.IsolatedAsyncioTestCase):
    async def test_idle_needs_recent_device_reply_and_no_unreflected_input(self):
        state = recovery.RecoveryState()
        obj = server()
        now = asyncio.get_running_loop().time()
        obj._active_service = object()
        obj._last_good_au_t = now - 30
        self.assertFalse(state.visual_idle(obj, now))
        state.last_control_ok = now
        self.assertTrue(state.visual_idle(obj, now))
        self.assertTrue(state.defer_watchdog(obj, now))
        state.last_input_t = now - 5
        self.assertFalse(state.visual_idle(obj, now))
        self.assertFalse(state.defer_watchdog(obj, now))
        state.last_input_t = 0
        state.last_control_ok = now - 16
        self.assertFalse(state.visual_idle(obj, now))
        state.last_control_ok = now
        state.control_failed = True
        self.assertFalse(state.visual_idle(obj, now))

    async def test_control_probe_discards_sessions_and_is_rate_limited(self):
        state = recovery.RecoveryState()
        obj = server()
        obj._active_service = object()
        obj._subscribers = {"viewer": object()}
        obj._last_good_au_t = asyncio.get_running_loop().time() - 30
        obj._rsd = object()
        calls = []

        class Service:
            def __init__(self, rsd): pass
            async def connect(self): calls.append("connect")
            async def get_media_stream_server_status(self):
                calls.append("query")
                return {"sessions": "synthetic-private-session"}
            async def close(self): calls.append("close")

        module = SimpleNamespace(DisplayService=Service, _is_tunnel_dead_error=recovery.closed_userspace)
        state.probe_if_quiet(obj, module)
        await state.control_task
        self.assertEqual(calls, ["connect", "query", "close"])
        self.assertEqual(state.control_ok_count, 1)
        self.assertNotIn("synthetic-private-session", str(vars(state)))
        state.probe_if_quiet(obj, module)
        self.assertEqual(calls, ["connect", "query", "close"])

    async def test_control_error_cannot_mask_disconnected_device(self):
        state = recovery.RecoveryState()
        obj = server()
        obj._active_service = object()
        obj._subscribers = {"viewer": object()}
        obj._last_good_au_t = asyncio.get_running_loop().time() - 30
        obj._rsd = object()
        state.last_control_ok = asyncio.get_running_loop().time()

        class Service:
            def __init__(self, rsd): pass
            async def connect(self): raise ConnectionError("userspace dial plane is closed")
            async def close(self): pass

        module = SimpleNamespace(DisplayService=Service, _is_tunnel_dead_error=recovery.closed_userspace)
        state.probe_if_quiet(obj, module)
        await state.control_task
        self.assertTrue(state.control_failed)
        self.assertTrue(state.fresh_tunnel.is_set())
        self.assertFalse(state.visual_idle(obj, asyncio.get_running_loop().time()))

    async def test_diagnostic_hold_defers_forced_restart_only_until_expiry(self):
        state = recovery.RecoveryState()
        obj = server()
        obj._active_service = object()
        state.watchdog_hold_until = asyncio.get_running_loop().time() + 90
        calls = []

        async def start(obj, force): calls.append(force)

        await state.ensure(obj, start, True)
        self.assertEqual(calls, [])
        state.watchdog_hold_until = 0
        await state.ensure(obj, start, True)
        self.assertEqual(calls, [True])

    async def test_concurrent_requests_share_one_start(self):
        state = recovery.RecoveryState()
        obj = server()
        gate = asyncio.Event()
        calls = []

        async def start(obj, force):
            calls.append(force)
            await gate.wait()
            obj._active_service = object()
            obj._stream_dirty = False

        a = asyncio.create_task(state.ensure(obj, start, True))
        b = asyncio.create_task(state.ensure(obj, start, True))
        await asyncio.sleep(0.01)
        gate.set()
        await asyncio.gather(a, b)
        self.assertEqual(calls, [True])
        self.assertEqual(state.joined, 1)
        await state.ensure(obj, start, True)
        self.assertEqual(calls, [True])
        self.assertEqual(state.deferred, 1)

    async def test_cancelled_caller_does_not_cancel_shared_recovery(self):
        state = recovery.RecoveryState()
        obj = server()
        gate = asyncio.Event()

        async def start(obj, force):
            await gate.wait()
            obj._active_service = object()

        caller = asyncio.create_task(state.ensure(obj, start, True))
        await asyncio.sleep(0.01)
        caller.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await caller
        gate.set()
        await state.task
        self.assertEqual(state.outcome, "ready")

    async def test_dead_tunnel_signals_worker_restart_and_stops_old_rsd(self):
        state = recovery.RecoveryState()
        calls = []

        async def start(obj, force):
            calls.append(force)
            error = RuntimeError("wrapper")
            error.__cause__ = ConnectionError("userspace dial plane is closed")
            raise error

        with self.assertRaises(RuntimeError):
            await state.ensure(server(), start, False)
        self.assertTrue(state.fresh_tunnel.is_set())
        with self.assertRaises(recovery.FreshTunnelRequired):
            await state.ensure(server(), start, True)
        self.assertEqual(calls, [False])

    async def test_upstream_errno_disconnection_also_rebuilds_worker(self):
        from pymobiledevice3.remote.core_device.screen_stream import _is_tunnel_dead_error
        state = recovery.RecoveryState()

        async def start(obj, force):
            raise ConnectionResetError("reset")

        with self.assertRaises(ConnectionResetError):
            await state.ensure(server(), start, True, _is_tunnel_dead_error)
        self.assertTrue(state.fresh_tunnel.is_set())

    async def test_timed_out_start_is_cancelled_and_cooldown_applies_to_codec(self):
        state = recovery.RecoveryState()
        obj = server()
        cancelled = asyncio.Event()

        async def start(obj, force):
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()

        old = recovery.RESTART_TIMEOUT
        recovery.RESTART_TIMEOUT = 0.02
        try:
            with self.assertRaises(TimeoutError):
                await state.ensure(obj, start, True)
            self.assertTrue(cancelled.is_set())
            self.assertEqual(state.outcome, "timeout")
            await state.ensure(obj, start, False)
            self.assertEqual(state.attempts, 1)
        finally:
            recovery.RESTART_TIMEOUT = old

    async def test_failed_starts_have_absolute_limit(self):
        state = recovery.RecoveryState()
        obj = server()

        async def start(obj, force):
            raise ValueError("unrelated start error")

        for _ in range(3):
            state.last_attempt = None
            with self.assertRaises(ValueError):
                await state.ensure(obj, start, True)
        state.last_attempt = None
        with self.assertRaisesRegex(RuntimeError, "3 failed starts"):
            await state.ensure(obj, start, False)
        self.assertEqual(state.attempts, 3)
        self.assertFalse(state.fresh_tunnel.is_set())

    async def test_missing_active_service_retries_without_watchdog(self):
        state = recovery.RecoveryState()
        obj = server()
        obj._subscribers = {"viewer": object()}
        calls = []

        async def start(obj, force):
            calls.append(force)
            if len(calls) == 1:
                raise ValueError("failed start")
            obj._active_service = object()

        obj._ensure_fresh_stream = lambda force: state.ensure(obj, start, force)
        with self.assertRaises(ValueError):
            await state.ensure(obj, start, False)
        await state.retry_if_inactive(obj)
        self.assertEqual(calls, [False], "cooldown must prevent fast retries")
        state.last_attempt -= recovery.RESTART_COOLDOWN
        await state.retry_if_inactive(obj)
        self.assertEqual(calls, [False, True])
        self.assertEqual(state.outcome, "ready")
        self.assertEqual(state.consecutive_failures, 0)

    async def test_snapshot_has_only_content_free_counters(self):
        state = recovery.RecoveryState()
        obj = server()
        obj._last_good_au_t = 0
        obj._rtp_packets_received = 13
        obj._subscribers = {asyncio.Queue(): SimpleNamespace(needs_key=True)}
        obj.private_token = "must never be returned"
        snapshot = state.snapshot(obj)
        self.assertEqual(snapshot["packets"], 13)
        self.assertEqual(snapshot["needs_key"], 1)
        self.assertNotIn("must never be returned", str(snapshot))
        self.assertIsNone(snapshot["au_age"])

    async def test_dead_tunnel_cancels_worker_and_runs_server_cleanup(self):
        from pymobiledevice3.remote.core_device import screen_stream
        cleaned = asyncio.Event()

        class FakeServer:
            _udp_recv_and_depacketize = screen_stream.ScreenStreamServer._udp_recv_and_depacketize
            _stall_watchdog = screen_stream.ScreenStreamServer._stall_watchdog

            async def _ensure_fresh_stream(self, force=False):
                raise ConnectionError("userspace dial plane is closed")

            async def serve(self):
                stop_event = asyncio.Event()
                try:
                    # Match upstream's eager-start behavior: it swallows a
                    # failed start then serves HTTP. Our signal must survive.
                    try:
                        await self._ensure_fresh_stream()
                    except Exception:
                        pass
                    await stop_event.wait()
                finally:
                    self.cleaned.set()

        module = SimpleNamespace(**vars(screen_stream))
        module.ScreenStreamServer = FakeServer

        def replace_once(source, old, new):
            self.assertEqual(source.count(old), 1)
            return source.replace(old, new, 1)

        recovery.install_recovery(module, replace_once)
        obj = FakeServer()
        obj._active_service = None
        obj._stream_dirty = True
        obj.cleaned = cleaned
        with self.assertRaises(recovery.FreshTunnelRequired):
            await asyncio.wait_for(obj.serve(), timeout=1)
        self.assertTrue(cleaned.is_set())
        self.assertTrue(obj._gym_recovery.task.done())
        self.assertTrue(module._is_tunnel_dead_error(ConnectionError("userspace dial plane is closed")))


class ClassificationChecks(unittest.TestCase):
    def test_udp_wire_checksum_and_boundaries(self):
        # ::1 -> ::2, source 100, destination 200, empty UDP, checksum feaf.
        packet = bytes.fromhex('6000000000081140' + '00' * 15 + '01' + '00' * 15 + '02' + '006400c80008feaf')
        self.assertTrue(recovery.udp6_checksum_valid(packet))
        damaged = bytearray(packet)
        damaged[-1] ^= 1
        self.assertFalse(recovery.udp6_checksum_valid(damaged))
        self.assertFalse(recovery.udp6_checksum_valid(packet + b'extra'))
        self.assertIsNone(recovery.udp6_checksum_valid(b'short'))
    def test_classification_is_exact_and_cycle_safe(self):
        closed = ConnectionError("userspace dial plane is closed")
        wrapped = RuntimeError("wrapper")
        wrapped.__context__ = closed
        self.assertTrue(recovery.closed_userspace(wrapped))
        self.assertFalse(recovery.closed_userspace(ConnectionError("unrelated")))
        self.assertFalse(recovery.closed_userspace(ValueError(str(closed))))
        cycle = ValueError("cycle")
        cycle.__cause__ = cycle
        self.assertFalse(recovery.closed_userspace(cycle))

    def test_supervisor_bounds_and_non_tunnel_errors(self):
        calls = []
        sleeps = []

        def run(command):
            calls.append(command)
            return SimpleNamespace(returncode=75)

        with redirect_stdout(io.StringIO()):
            status = recovery.supervise(["worker"], run=run, sleep=sleeps.append, now=lambda: 0)
        self.assertEqual(status, 75)
        self.assertEqual(len(calls), 4)
        self.assertEqual(sleeps, [2, 5, 10])
        self.assertEqual(recovery.supervise([], run=lambda _: SimpleNamespace(returncode=1)), 1)

    def test_supervisor_retry_window_expires(self):
        codes = iter([75, 75, 75, 75, 0])
        times = iter([0, 1, 2, 301])
        sleeps = []
        with redirect_stdout(io.StringIO()):
            status = recovery.supervise([], run=lambda _: SimpleNamespace(returncode=next(codes)),
                                        sleep=sleeps.append, now=lambda: next(times))
        self.assertEqual(status, 0)
        self.assertEqual(sleeps, [2, 5, 10, 5])

    def test_ctrl_c_does_not_restart(self):
        def run(_):
            raise KeyboardInterrupt
        self.assertEqual(recovery.supervise([], run=run), 130)


if __name__ == "__main__":
    unittest.main()
