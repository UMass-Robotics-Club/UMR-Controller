"""Manual bluetooth test for umr_controller.

Run it, connect the phone app, and move the joysticks. Prints the latest
command 10 times a second until an E-Stop happens.
"""

import logging
import time

from umr_controller import ControllerInterface

logging.basicConfig(level=logging.INFO)

with ControllerInterface() as c:
    print("waiting for phone...")
    while True:
        s = c.estop_status()
        if s.active:
            print("E-STOP:", s.source.value)
            break
        print(c.get_command().as_array())
        time.sleep(0.1)
