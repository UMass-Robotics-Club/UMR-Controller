"""Data types shared by the real and mock controller interfaces."""

import enum
import time
from dataclasses import dataclass, field
from typing import Optional

import numpy as np


# The BLE advert only fits the service UUID plus about 8 bytes of name.
# Longer names get dropped (the app shows the host's name instead).
MAX_DEVICE_NAME_BYTES = 8


@dataclass(frozen=True)
class ControllerConfig:
    device_name: str  # name shown in the phone app's robot list, required
    link_timeout_s: float = 0.5

    def __post_init__(self) -> None:
        if not self.device_name.strip():
            raise ValueError("device_name can't be empty")
        if len(self.device_name.encode("utf-8")) > MAX_DEVICE_NAME_BYTES:
            raise ValueError(
                f"device_name {self.device_name!r} is too long, "
                f"max {MAX_DEVICE_NAME_BYTES} characters"
            )


@dataclass(frozen=True)
class ControllerCommand:
    """Latest joystick command. Each axis is in the range -1 to 1."""

    vx: float = 0.0  # forward (+) / back (-)
    vy: float = 0.0  # right (+) / left (-)
    yaw: float = 0.0  # rotate right (+) / left (-)
    timestamp: float = field(default_factory=time.perf_counter)

    def as_array(self) -> np.ndarray:
        return np.array([self.vx, self.vy, self.yaw], dtype=np.float32)


class EStopSource(enum.Enum):
    BUTTON = "BUTTON"
    LINK_LOST = "LINK_LOST"


@dataclass(frozen=True)
class EStopStatus:
    active: bool = False
    source: Optional[EStopSource] = None
    timestamp: Optional[float] = None  # time.perf_counter() when it triggered
