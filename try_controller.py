"""Manual bluetooth test for umr_controller.

Run it, connect the phone app, and move the joysticks. Prints the latest
command 10 times a second until an E-Stop happens.
"""

import logging
import time

from umr_controller import ControllerConfig, ControllerInterface
ROBOT_NAME = "Doggy"  # name shown in the phone app's robot list

logging.basicConfig(level=logging.INFO)

with ControllerInterface(ControllerConfig(device_name=ROBOT_NAME)) as c:
    print("waiting for phone...")
    while not c.connected():
        time.sleep(0.1)
    print("phone connected")

    while True:
        s = c.estop_status()
        if s.active:
            print("E-STOP:", s.source.value)
            break
        print(c.get_command().as_array())
        time.sleep(0.1)
