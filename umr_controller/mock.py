"""Fake controller with the same functions as ControllerInterface.

Use it to test the onboard code without a phone or bluetooth.
"""

import time
from typing import Optional, Tuple

from .models import ControllerCommand, ControllerConfig, EStopSource, EStopStatus


class MockControllerInterface:
    def __init__(
        self,
        config: Optional[ControllerConfig] = None,
        command: Tuple[float, float, float] = (0.0, 0.0, 0.0),
        estop_after_s: Optional[float] = None,
        estop_source: EStopSource = EStopSource.BUTTON,
    ) -> None:
        """
        command: fixed (vx, vy, yaw) returned by get_command()
        estop_after_s: trigger the E-Stop this many seconds after start()
        estop_source: source reported when estop_after_s triggers
        """
        self.config = config or ControllerConfig()
        self._command = command
        self._estop_after_s = estop_after_s
        self._estop_source = estop_source
        self._start_time: Optional[float] = None
        self._estop = EStopStatus()

    def start(self) -> None:
        self._start_time = time.perf_counter()
        self._estop = EStopStatus()

    def close(self) -> None:
        pass

    def __enter__(self) -> "MockControllerInterface":
        self.start()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def connected(self) -> bool:
        return self._start_time is not None

    def get_command(self) -> ControllerCommand:
        vx, vy, yaw = self._command
        return ControllerCommand(vx=vx, vy=vy, yaw=yaw)

    def estop_active(self) -> bool:
        return self.estop_status().active

    def estop_status(self) -> EStopStatus:
        if (
            not self._estop.active
            and self._estop_after_s is not None
            and self._start_time is not None
        ):
            trigger_time = self._start_time + self._estop_after_s
            if time.perf_counter() >= trigger_time:
                self._estop = EStopStatus(True, self._estop_source, trigger_time)
        return self._estop

    # test helpers, not part of the real interface

    def set_command(self, vx: float, vy: float, yaw: float) -> None:
        self._command = (vx, vy, yaw)

    def press_estop(self, source: EStopSource = EStopSource.BUTTON) -> None:
        if not self._estop.active:
            self._estop = EStopStatus(True, source, time.perf_counter())
