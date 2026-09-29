import time
from umr_controller import ControllerInterface, ControllerConfig, EStopSource
from umr_controller.interface import parse_command

# (x,y,z) from the app -> vx=y, vy=x, yaw=z
c = parse_command("(1,-1,0)", 0.0)
assert (c.vx, c.vy, c.yaw) == (-1, 1, 0)
assert parse_command("garbage", 0.0) is None

# lost connection
ci = ControllerInterface(ControllerConfig(link_timeout_s=0.1))
time.sleep(0.2)
assert not ci.estop_active()              # no trigger before the first message
ci._handle_message("(0,1,0)")
assert ci.get_command().vx == 1.0
time.sleep(0.15)
assert ci.estop_status().source is EStopSource.LINK_LOST
ci._handle_message("(0,1,0)")
assert ci.estop_active()                  # stays on

# button
ci2 = ControllerInterface()
ci2._handle_message("ESTOP")
assert ci2.estop_status().source is EStopSource.BUTTON

import time
from umr_controller import MockControllerInterface

with MockControllerInterface(command=(1, 0, 0), estop_after_s=3) as c:
    while not c.estop_active():
        print(c.get_command().as_array())
        time.sleep(0.5)
    print("stopped:", c.estop_status())

print("all checks passed")