# Controller package spec

**tl;dr** `ControllerInterface` (package `umr_controller`) receives the joystick command and the E-Stop from the phone app over bluetooth. `MockControllerInterface` has the same functions, for testing.

## Usage

```python
from umr_controller import ControllerConfig, ControllerInterface

config = ControllerConfig(device_name="Doggy")   # name is required, max 8 characters
with ControllerInterface(config) as controller:
    ...
```

`with` calls `start()` at the top and `close()` at the end, even if the code crashes.

## Functions

| Function | Returns | What it does |
| --- | --- | --- |
| `ControllerInterface(config)` | the controller | Creates it. `config` must have a `device_name`. |
| `start()` | `None` | Starts the bluetooth server in a background thread and advertises `device_name`. Also resets the E-Stop flag, the command and `connected()`. Waits up to 10 s for bluetooth to come up, raises `ControllerConnectionError` if it can't. |
| `connected()` | `bool` | True once the phone has sent its first message since `start()`. |
| `get_command()` | `ControllerCommand` | Latest joystick command. All zeros if nothing has arrived yet. |
| `estop_active()` | `bool` | True if the E-Stop has been triggered. Also checks for a lost connection. |
| `estop_status()` | `EStopStatus` | Same check, plus the source (`BUTTON` or `LINK_LOST`) and the time it triggered. For logging. |
| `close()` | `None` | Stops the bluetooth server and the background thread. Safe to call more than once. |

Everything except `start()` returns right away, the bluetooth stuff runs in a background thread.

`MockControllerInterface(config=None, command=(0, 0, 0), estop_after_s=None)` has the same functions. It returns `command` as the joystick, and triggers the E-Stop `estop_after_s` seconds after `start()`. `set_command(vx, vy, yaw)` and `press_estop()` change it mid-test.

## Data format

**ControllerConfig:** `device_name` (required, 1 to 8 characters), `link_timeout_s` (default 0.5).

**ControllerCommand:** `vx` (forward/back), `vy` (left/right), `yaw` (rotate), each -1 to 1, plus a `timestamp` from `time.perf_counter()`. `as_array()` gives a float32 `[vx, vy, yaw]`.

**EStopStatus:** `active` (bool), `source` (`EStopSource.BUTTON`, `EStopSource.LINK_LOST` or `None`), `timestamp` (`time.perf_counter()` when it triggered, or `None`).

## Robot name

Every robot has to pass its own `device_name`, there is no default. The phone app lists every robot it can see by that name, and you tap the one you want to control.

Max 8 characters, because the bluetooth advert only has room for the service ID plus about 8 bytes of name. A longer name gets dropped and the app shows the computer's name instead.

What happens if it's wrong:

| Code | Result |
| --- | --- |
| `ControllerInterface()` (no config) | `TypeError` |
| `ControllerConfig()` (no name) | `TypeError` |
| `ControllerConfig(device_name="")` or only spaces | `ValueError` |
| `ControllerConfig(device_name="UMR-Doggy")` (more than 8 characters) | `ValueError` |

Not checked by the package: names should be unique. Two robots with the same name look the same in the app's list.

## E-Stop

- Triggers: the app's E-STOP button, or no bluetooth message for `link_timeout_s` (0.5 s)
- Stays on until `start()` is called again, which resets the flag to False
- Lost connection only counts after the first message

## Bluetooth messages (phone → robot)

UTF-8 text on the write characteristic `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`.

| Message | Meaning |
| --- | --- |
| `(x,y,z)` | joystick, every 50 ms |
| `ESTOP` | E-STOP button, sent 5 times, 20 ms apart |

Anything else gets logged and ignored.

## Errors

`start()` raises `ControllerConnectionError` if bluetooth can't start. A missing, empty or too long robot name raises `TypeError` / `ValueError` (see Robot name). Everything else goes through `estop_active()` / `estop_status()`.
