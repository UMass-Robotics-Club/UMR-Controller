"""Receives joystick commands and the E-Stop from the phone app over BLE.

The BLE server runs in a background thread. The public methods only read
state that the thread has already stored, so none of them block.
"""

import asyncio
import logging
import re
import threading
import time
from typing import Optional

from .errors import ControllerConnectionError
from .models import (
    ControllerCommand,
    ControllerConfig,
    EStopSource,
    EStopStatus,
)

SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
WRITE_CHARACTERISTIC_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
ESTOP_MESSAGE = "ESTOP"
START_TIMEOUT_S = 10.0

# Joystick message sent by the app, e.g. "(0,1,-1)" = (x, y, z)
COMMAND_PATTERN = re.compile(
    r"^\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$"
)

log = logging.getLogger(__name__)


def parse_command(text: str, timestamp: float) -> Optional[ControllerCommand]:
    """Turn an "(x,y,z)" message into a ControllerCommand, or None if invalid.

    The app sends x = left/right, y = forward/back, z = rotate.
    """
    match = COMMAND_PATTERN.match(text)
    if match is None:
        return None

    x, y, z = (max(-1.0, min(1.0, float(v))) for v in match.groups())
    return ControllerCommand(vx=y, vy=x, yaw=z, timestamp=timestamp)


class ControllerInterface:
    def __init__(self, config: Optional[ControllerConfig] = None) -> None:
        self.config = config or ControllerConfig()

        self._lock = threading.Lock()
        self._command = ControllerCommand()
        self._estop = EStopStatus()
        self._last_msg_time: Optional[float] = None  # None = no message yet

        self._thread: Optional[threading.Thread] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._stop_event: Optional[asyncio.Event] = None
        self._ready = threading.Event()
        self._startup_error: Optional[BaseException] = None

    # lifecycle

    def start(self) -> None:
        """Start listening for the phone. Also clears a previous E-Stop."""
        with self._lock:
            self._command = ControllerCommand()
            self._estop = EStopStatus()
            self._last_msg_time = None

        if self._thread is not None and self._thread.is_alive():
            return

        self._ready.clear()
        self._startup_error = None
        self._thread = threading.Thread(
            target=self._run_ble, name="umr-controller-ble", daemon=True
        )
        self._thread.start()

        if not self._ready.wait(START_TIMEOUT_S):
            raise ControllerConnectionError(
                f"Bluetooth server did not start within {START_TIMEOUT_S} s"
            )
        if self._startup_error is not None:
            raise ControllerConnectionError(
                f"Bluetooth server failed to start: {self._startup_error}"
            ) from self._startup_error

    def close(self) -> None:
        """Stop listening. Safe to call more than once."""
        if self._loop is not None and self._stop_event is not None:
            self._loop.call_soon_threadsafe(self._stop_event.set)
        if self._thread is not None:
            self._thread.join(timeout=2.0)
        self._thread = None

    def __enter__(self) -> "ControllerInterface":
        self.start()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    # data

    def get_command(self) -> ControllerCommand:
        with self._lock:
            return self._command

    def estop_active(self) -> bool:
        return self.estop_status().active

    def estop_status(self) -> EStopStatus:
        with self._lock:
            self._check_link()
            return self._estop

    # internals

    def _check_link(self) -> None:
        """Latch a LINK_LOST E-Stop if the phone has gone quiet. Needs the lock."""
        if self._estop.active or self._last_msg_time is None:
            return

        now = time.perf_counter()
        if now - self._last_msg_time > self.config.link_timeout_s:
            self._estop = EStopStatus(True, EStopSource.LINK_LOST, now)
            log.warning(
                "E-Stop: no message for %.2f s", now - self._last_msg_time
            )

    def _handle_message(self, text: str) -> None:
        now = time.perf_counter()
        text = text.strip()

        with self._lock:
            self._check_link()
            self._last_msg_time = now

            if text == ESTOP_MESSAGE:
                if not self._estop.active:
                    self._estop = EStopStatus(True, EStopSource.BUTTON, now)
                    log.warning("E-Stop: button pressed on controller")
                return

            command = parse_command(text, now)
            if command is None:
                log.warning("Ignoring unknown message: %r", text)
                return
            self._command = command

    def _on_write(self, characteristic: object, value: bytearray, **_: object) -> None:
        try:
            text = bytes(value).decode("utf-8")
        except UnicodeDecodeError as exc:
            log.warning("Failed to decode BLE payload: %s", exc)
            return
        self._handle_message(text)

    def _run_ble(self) -> None:
        try:
            asyncio.run(self._serve())
        except Exception as exc:
            if self._ready.is_set():
                log.exception("Bluetooth server stopped unexpectedly")
                return
            self._startup_error = exc
            self._ready.set()

    async def _serve(self) -> None:
        try:
            from bless import (
                BlessServer,
                GATTAttributePermissions,
                GATTCharacteristicProperties,
            )
        except ImportError as exc:
            raise ControllerConnectionError(
                "Missing dependency 'bless'. Install with: pip3 install bless"
            ) from exc

        self._loop = asyncio.get_running_loop()
        self._stop_event = asyncio.Event()

        server = BlessServer(name=self.config.device_name)
        server.write_request_func = self._on_write

        await server.add_new_service(SERVICE_UUID)
        await server.add_new_characteristic(
            SERVICE_UUID,
            WRITE_CHARACTERISTIC_UUID,
            GATTCharacteristicProperties.write
            | GATTCharacteristicProperties.write_without_response,
            None,
            GATTAttributePermissions.writeable,
        )
        await server.start()
        log.info("Bluetooth server running as %s", self.config.device_name)
        self._ready.set()

        try:
            await self._stop_event.wait()
        finally:
            await server.stop()
            self._loop = None
            self._stop_event = None
