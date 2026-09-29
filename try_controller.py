"""Manual bluetooth test for umr_controller.

Run it, connect the phone app, and move the joysticks. 10 times a second it
prints the latest command and the longest gap between phone messages since
the last line, until an E-Stop happens.
"""

import logging
import time

from umr_controller import ControllerConfig, ControllerInterface

ROBOT_NAME = "Doggy"  # name shown in the phone app's robot list
PRINT_INTERVAL_S = 0.1

logging.basicConfig(level=logging.INFO)

with ControllerInterface(ControllerConfig(device_name=ROBOT_NAME)) as c:
    print("waiting for phone...")
    while not c.connected():
        time.sleep(0.1)
    print("phone connected")

    last_msg_time = c.get_command().timestamp
    max_gap = 0.0
    worst_gap = 0.0
    next_print = time.perf_counter() + PRINT_INTERVAL_S

    while True:
        s = c.estop_status()
        if s.active:
            gap_now = time.perf_counter() - last_msg_time
            print("E-STOP:", s.source.value)
            print(f"longest gap overall: {max(worst_gap, max_gap, gap_now) * 1000:.0f} ms")
            break

        # Every phone message creates a new command with a new timestamp
        command = c.get_command()
        if command.timestamp != last_msg_time:
            max_gap = max(max_gap, command.timestamp - last_msg_time)
            last_msg_time = command.timestamp

        now = time.perf_counter()
        if now >= next_print:
            # Include the gap still in progress, in case nothing arrived since the last line
            gap = max(max_gap, now - last_msg_time)
            worst_gap = max(worst_gap, gap)
            print(f"{command.as_array()}  longest gap: {gap * 1000:.0f} ms")
            max_gap = 0.0
            next_print = now + PRINT_INTERVAL_S

        time.sleep(0.005)
