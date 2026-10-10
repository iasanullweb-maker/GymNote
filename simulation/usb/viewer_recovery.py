"""Bounded recovery and content-free counters for the local USB viewer."""
import asyncio
from collections import deque
import contextlib
import inspect
import json
import os
import subprocess
import textwrap
import time

FRESH_TUNNEL_EXIT = 75
RESTART_TIMEOUT = 12.0
RESTART_COOLDOWN = 15.0


class FreshTunnelRequired(RuntimeError):
    """The current worker must end before a fresh CLI tunnel can be made."""


def closed_userspace(error):
    seen = set()
    while error is not None and id(error) not in seen:
        seen.add(id(error))
        if isinstance(error, ConnectionError) and str(error) == "userspace dial plane is closed":
            return True
        error = error.__cause__ or error.__context__
    return False


class RecoveryState:
    def __init__(self):
        self.task = None
        self.last_attempt = None
        self.generation = 0
        self.attempts = 0
        self.joined = 0
        self.deferred = 0
        self.failures = 0
        self.consecutive_failures = 0
        self.outcome = "idle"
        self.fresh_tunnel = asyncio.Event()
        self.counters = dict(au=0, gaps=0, reorders=0, corrupt=0, http_messages=0)

    async def ensure(self, server, original, force, is_dead=closed_userspace):
        if self.fresh_tunnel.is_set():
            raise FreshTunnelRequired("fresh USB tunnel required")
        if self.task is not None and not self.task.done():
            self.joined += 1
            return await asyncio.shield(self.task)
        now = asyncio.get_running_loop().time()
        if not force and server._active_service is not None and not server._stream_dirty:
            return
        if self.consecutive_failures >= 3 and server._active_service is None:
            raise RuntimeError("USB stream recovery stopped after 3 failed starts")
        if self.last_attempt is not None and now - self.last_attempt < RESTART_COOLDOWN:
            self.deferred += 1
            return
        self.last_attempt = now
        self.generation += 1
        self.attempts += 1
        self.outcome = "running"

        async def perform():
            try:
                await asyncio.wait_for(original(server, force=force), RESTART_TIMEOUT)
                self.outcome = "ready"
                self.consecutive_failures = 0
            except Exception as error:
                self.failures += 1
                self.consecutive_failures += 1
                self.outcome = "timeout" if isinstance(error, TimeoutError) else "failed"
                if is_dead(error):
                    self.outcome = "fresh-tunnel-required"
                    self.fresh_tunnel.set()
                raise

        self.task = asyncio.create_task(perform(), name="gymnote-stream-recovery")
        # A disconnected HTTP caller must not cancel recovery or leave an
        # unobserved exception after shield detached its waiter.
        self.task.add_done_callback(lambda task: task.exception() if not task.cancelled() else None)
        return await asyncio.shield(self.task)

    def snapshot(self, server):
        now = asyncio.get_running_loop().time()
        last = server._last_good_au_t
        return {
            "worker_pid": os.getpid(), "seconds": round(now, 3),
            "generation": self.generation, "packets": server._rtp_packets_received,
            **self.counters,
            "au_age": round(max(0, now - last), 3) if last else None,
            "viewers": len(server._subscribers),
            "queued": sum(q.qsize() for q in server._subscribers),
            "needs_key": sum(int(s.needs_key) for s in server._subscribers.values()),
            "active": server._active_service is not None,
            "recovery": self.outcome, "attempts": self.attempts,
            "joined": self.joined, "deferred": self.deferred, "failures": self.failures,
        }

    async def retry_if_inactive(self, server):
        now = asyncio.get_running_loop().time()
        if (server._subscribers and server._active_service is None
                and self.outcome in ("failed", "timeout")
                and self.consecutive_failures < 3
                and self.last_attempt is not None
                and now - self.last_attempt >= RESTART_COOLDOWN):
            with contextlib.suppress(Exception):
                await server._ensure_fresh_stream(force=True)


def state_for(server):
    if not hasattr(server, "_gym_recovery"):
        server._gym_recovery = RecoveryState()
    return server._gym_recovery


def install_recovery(module, replace_once):
    cls = module.ScreenStreamServer
    original_ensure = cls._ensure_fresh_stream
    # Keep upstream serve in the CLI's own task: its shutdown cancels all
    # other loop tasks, so a separate supervisor task would be cancelled too.
    serve_source = textwrap.dedent(inspect.getsource(cls.serve))
    serve_source = replace_once(serve_source, "await stop_event.wait()", "await self._gym_wait_for_stop(stop_event)")
    serve_namespace = dict(vars(module))
    exec(compile(serve_source, "<gymnote-usb-server-lifetime>", "exec"), serve_namespace)
    original_serve = serve_namespace["serve"]
    original_classifier = module._is_tunnel_dead_error
    module._is_tunnel_dead_error = lambda error: closed_userspace(error) or original_classifier(error)

    async def ensure(self, force=False):
        return await state_for(self).ensure(self, original_ensure, force, module._is_tunnel_dead_error)

    async def health_http(self, writer):
        body = json.dumps(state_for(self).snapshot(self), separators=(",", ":")).encode()
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
        await writer.drain()
        writer.close()

    async def serve(self):
        state = state_for(self)
        async def monitor():
            while True:
                await asyncio.sleep(2)
                print("USB_COUNTERS " + json.dumps(state.snapshot(self), separators=(",", ":")), flush=True)
                # A failed start leaves no active service, so upstream's
                # watchdog stops checking. Retry here with the same bounds.
                await state.retry_if_inactive(self)
        monitoring = asyncio.create_task(monitor())
        try:
            await original_serve(self)
            if state.fresh_tunnel.is_set():
                raise FreshTunnelRequired("fresh USB tunnel required")
        finally:
            monitoring.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await monitoring
            if state.task is not None and not state.task.done():
                state.task.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await state.task

    async def wait_for_stop(self, stop_event):
        stopping = asyncio.create_task(stop_event.wait())
        dead = asyncio.create_task(state_for(self).fresh_tunnel.wait())
        try:
            await asyncio.wait([stopping, dead], return_when=asyncio.FIRST_COMPLETED)
        finally:
            for task in (stopping, dead):
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task

    # Instrument only counts, never RTP payloads, HID bodies or identifiers.
    source = textwrap.dedent(inspect.getsource(cls._udp_recv_and_depacketize))
    for old, counter in [
        ("self._last_good_au_t = loop.time()", "au"),
        ("stats_forward_gaps += 1", "gaps"),
        ("stats_reorders += 1", "reorders"),
        ("stats_corrupt_aus += 1", "corrupt"),
    ]:
        source = replace_once(source, old, old + "; self._gym_recovery.counters['" + counter + "'] += 1")
    namespace = dict(vars(module))
    exec(compile(source, "<gymnote-usb-counters>", "exec"), namespace)
    instrumented_recv = namespace["_udp_recv_and_depacketize"]

    async def receive(self, transport):
        state_for(self)
        return await instrumented_recv(self, transport)

    cls._udp_recv_and_depacketize = receive
    cls._ensure_fresh_stream = ensure
    cls._gym_health_http = health_http
    cls._gym_wait_for_stop = wait_for_stop
    cls.serve = serve


def supervise(worker_command, *, run=subprocess.run, sleep=time.sleep, now=time.monotonic):
    """Only retry the explicit dead-tunnel exit, at most 3 times per 5 min."""
    attempts = deque()
    try:
        while True:
            result = run(worker_command)
            if result.returncode != FRESH_TUNNEL_EXIT:
                return result.returncode
            instant = now()
            while attempts and instant - attempts[0] >= 300:
                attempts.popleft()
            if len(attempts) >= 3:
                print("USB recovery stopped after 3 fresh-tunnel retries in 5 minutes.", flush=True)
                return FRESH_TUNNEL_EXIT
            attempts.append(instant)
            delay = (2, 5, 10)[len(attempts) - 1]
            print(f"USB tunnel closed; creating a fresh worker in {delay}s.", flush=True)
            sleep(delay)
    except KeyboardInterrupt:
        return 130
