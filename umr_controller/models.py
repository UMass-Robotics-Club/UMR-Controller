"""Data types shared by the real and mock controller interfaces."""

import enum
import time
from dataclasses import dataclass, field
from typing import Optional

import numpy as np


@dataclass(frozen=True)
class ControllerConfig:
    device_name: str = "UMR-Robot"
    link_timeout_s: float = 0.5


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
