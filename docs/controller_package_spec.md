# Controller package spec

**tl;dr** `ControllerInterface` (package `umr_controller`) receives the joystick command and the E-Stop from the phone app over bluetooth. `MockControllerInterface` has the same functions, for testing.

## Functions

```python
controller = ControllerInterface(config)   # or MockControllerInterface(config) for testing
controller.start()           # start listening for the phone over bluetooth
controller.get_command()     # -> latest ControllerCommand
controller.estop_active()    # -> True/False
controller.estop_status()    # what triggered it and when (for logging)
controller.close()           # stop listening
```

None of these sleep or block, the bluetooth stuff runs in a background thread. `with ControllerInterface(config) as controller:` also works and makes sure `close()` runs.

## Data format

**ControllerCommand:** `vx` (forward/back), `vy` (left/right), `yaw` (rotate), each -1 to 1, plus a `timestamp` from `time.perf_counter()`. `as_array()` gives a float32 `[vx, vy, yaw]`. It's all zeros if the phone hasn't sent anything yet.

**Config:** `device_name` (default `"UMR-Robot"`), `link_timeout_s` (default 0.5).

## E-Stop

- Triggers: the app's shutdown button, or no bluetooth message for 0.5 s
- Stays on until `start()` is called again, which resets the flag to False
- `estop_status()` gives the source (`BUTTON` or `LINK_LOST`) and the time it happened
- Lost connection only counts after the first message

## Bluetooth messages (phone → robot)

UTF-8 text on the existing write characteristic `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`.

| Message | Meaning |
| --- | --- |
| `(x,y,z)` | joystick, every 50 ms (same as now) |
| `ESTOP` | shutdown button, sent 5 times, 20 ms apart |

Anything else gets logged and ignored.

## Errors

`start()` raises `ControllerConnectionError` if bluetooth can't start. Everything else goes through `estop_active()` / `estop_status()`.

