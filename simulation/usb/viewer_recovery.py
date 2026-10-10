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
import struct

FRESH_TUNNEL_EXIT = 75
RESTART_TIMEOUT = 12.0
RESTART_COOLDOWN = 15.0
WIRE_COUNTERS = dict(wire_udp=0, wire_bad_checksum=0, wire_rr=0, wire_rctl=0, wire_receipt=0)


def udp6_checksum_valid(packet):
    """Check the existing IPv6/UDP datagram; never retain its content."""
    if len(packet) < 48 or packet[0] >> 4 != 6 or packet[6] != 17:
        return None
    length = int.from_bytes(packet[44:46], "big")
    if length < 8 or len(packet) != 40 + length:
        return False
    pseudo = packet[8:40] + length.to_bytes(4, "big") + b"\x00\x00\x00\x11"
    data = pseudo + packet[40:]
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack("!" + "H" * (len(data) // 2), data))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return total == 65535


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
        self.watchdog_hold_until = 0
        self.last_input_t = 0
        self.control_task = None
        self.last_control_attempt = None
        self.last_control_ok = None
        self.control_failed = False
        self.control_ok_count = 0
        self.control_error_count = 0
        self.counters = dict(au=0, gaps=0, reorders=0, corrupt=0, http_messages=0,
                             rr_submitted=0, rctl_submitted=0, receipt_submitted=0, feedback_errors=0)

    async def ensure(self, server, original, force, is_dead=closed_userspace):
        if self.fresh_tunnel.is_set():
            raise FreshTunnelRequired("fresh USB tunnel required")
        if self.task is not None and not self.task.done():
            self.joined += 1
            return await asyncio.shield(self.task)
        now = asyncio.get_running_loop().time()
        if not force and server._active_service is not None and not server._stream_dirty:
            return
        if force and now < self.watchdog_hold_until and server._active_service is not None:
            self.deferred += 1
            return
        if self.consecutive_failures >= 3 and server._active_service is None:
            raise RuntimeError("USB stream recovery stopped after 3 failed starts")
        if self.last_attempt is not None and now - self.last_attempt < RESTART_COOLDOWN:
            self.deferred += 1
            return
        self.last_attempt = now
        self.generation += 1
        self.last_control_ok = None
        self.last_control_attempt = None
        self.control_failed = False
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
        transport = getattr(server, "_active_sock", None)
        peer = getattr(transport, "_gym_last_peer", None)
        destination = getattr(server, "_rtcp_dest", None)
        def alive(name):
            task = getattr(server, name, None)
            return task is not None and not task.done()
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
            "feedback_configured": destination is not None,
            "feedback_peer_matches_rtp": peer == destination if peer and destination else None,
            "feedback_ip_matches_rtp": peer[0] == destination[0] if peer and destination else None,
            "rtp_task_alive": alive("_active_recv_task"), "rr_task_alive": alive("_active_rtcp_task"),
            "rctl_task_alive": alive("_rctl_task"), "rctl_enabled": getattr(server, "_rctl_enabled", False),
            "watchdog_hold_seconds": round(max(0, self.watchdog_hold_until - now), 1),
            **WIRE_COUNTERS,
            "control_ok_count": self.control_ok_count, "control_error_count": self.control_error_count,
            "control_age": round(now - self.last_control_ok, 2) if self.last_control_ok is not None else None,
            "video_idle": self.visual_idle(server, now),
        }

    def visual_idle(self, server, now):
        # An RPC response proves device connectivity, not encoder health.
        # Do not call an idle picture healthy after unreflected remote input.
        return (server._active_service is not None and not self.control_failed
                and self.last_control_ok is not None and now - self.last_control_ok < 15
                and now - server._last_good_au_t >= 3
                and self.last_input_t <= server._last_good_au_t)

    def defer_watchdog(self, server, now):
        probing = (self.control_task is not None and not self.control_task.done()
                   and self.last_control_attempt is not None and now - self.last_control_attempt < 4)
        return self.visual_idle(server, now) or probing

    def probe_if_quiet(self, server, module):
        now = asyncio.get_running_loop().time()
        if (not server._subscribers or server._active_service is None
                or now - server._last_good_au_t < 2
                or (self.control_task is not None and not self.control_task.done())
                or (self.last_control_attempt is not None and now - self.last_control_attempt < 10)):
            return
        self.last_control_attempt = now
        generation = self.generation

        async def probe():
            service = module.DisplayService(server._rsd)
            try:
                async def query():
                    await service.connect()
                    # Discard the reply: it may contain session identifiers.
                    await service.get_media_stream_server_status()
                await asyncio.wait_for(query(), timeout=4)
                if generation == self.generation:
                    self.last_control_ok = asyncio.get_running_loop().time()
                    self.control_failed = False
                    self.control_ok_count += 1
            except Exception as error:
                if generation == self.generation:
                    self.control_failed = True
                    self.control_error_count += 1
                    if module._is_tunnel_dead_error(error):
                        self.fresh_tunnel.set()
            finally:
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await asyncio.wait_for(service.close(), timeout=2)
        self.control_task = asyncio.create_task(probe(), name="gymnote-device-connectivity")

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
    watchdog_source = textwrap.dedent(inspect.getsource(cls._stall_watchdog))
    watchdog_source = replace_once(watchdog_source,
                                  "        now = loop.time()\n        stalled =",
                                  "        now = loop.time()\n        if now < self._gym_recovery.watchdog_hold_until or self._gym_recovery.defer_watchdog(self, now):\n            continue\n        stalled =")
    watchdog_namespace = dict(vars(module))
    exec(compile(watchdog_source, "<gymnote-diagnostic-watchdog>", "exec"), watchdog_namespace)
    cls._stall_watchdog = watchdog_namespace["_stall_watchdog"]

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
                state.probe_if_quiet(self, module)
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
            if state.control_task is not None and not state.control_task.done():
                state.control_task.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await state.control_task

    async def wait_for_stop(self, stop_event):
        self._gym_stop_event = stop_event
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
        transport._gym_recovery_state = state_for(self)
        return await instrumented_recv(self, transport)

    # Trace local submission only, not device acknowledgement. Expose boolean
    # peer comparisons so addresses and ports stay out of diagnostic output.
    from pymobiledevice3.remote.userspace_tunnel import UserspaceUdp
    original_udp_recv = UserspaceUdp.recv
    recv_source = inspect.getsource(original_udp_recv)
    if recv_source.count("return await self._sock.recv(bufsize)") != 1:
        raise RuntimeError("Upstream userspace UDP changed; refusing unverified diagnostics")

    async def udp_receive(self, bufsize=65535):
        data, self._gym_last_peer = await self._sock.recvfrom(bufsize)
        return data

    def measured_send(original):
        async def send(self, data, ip, port):
            state = getattr(self, "_gym_recovery_state", None)
            try:
                await original(self, data, ip, port)
            except Exception:
                if state is not None:
                    state.counters["feedback_errors"] += 1
                raise
            if state is not None and len(data) >= 12:
                counter = ("rr_submitted" if data[1] == 201 else
                           "rctl_submitted" if data[8:12] == b"RCTL" else
                           "receipt_submitted" if data[8:12] == b"\x00\x00\x00\x05" else None)
                if counter:
                    state.counters[counter] += 1
        return send

    UserspaceUdp.recv = udp_receive
    UserspaceUdp.sendto = measured_send(UserspaceUdp.sendto)
    module._KernelUdp.sendto = measured_send(module._KernelUdp.sendto)
    from pymobiledevice3.remote.tunnel_service import RemotePairingTcpTunnel
    original_wire_send = RemotePairingTcpTunnel.send_packet_to_device

    async def wire_send(self, packet):
        valid = udp6_checksum_valid(packet)
        await original_wire_send(self, packet)
        if valid is not None:
            WIRE_COUNTERS["wire_udp"] += 1
            WIRE_COUNTERS["wire_bad_checksum"] += int(not valid)
            if len(packet) >= 60:
                counter = ("wire_rr" if packet[49] == 201 else
                           "wire_rctl" if packet[56:60] == b"RCTL" else
                           "wire_receipt" if packet[56:60] == b"\x00\x00\x00\x05" else None)
                if counter:
                    WIRE_COUNTERS[counter] += 1

    RemotePairingTcpTunnel.send_packet_to_device = wire_send

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
