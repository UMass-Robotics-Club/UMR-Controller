#!/usr/bin/env python3
"""BLE receiver for a Mac test host or Jetson robot.

This script exposes a writable BLE characteristic and prints incoming
command strings sent by the iOS remote app.
"""

import asyncio
import os
from datetime import datetime

try:
    from bless import (
        BlessServer,
        GATTAttributePermissions,
        GATTCharacteristicProperties,
    )
except ImportError as exc:
    raise SystemExit(
        "Missing dependency 'bless'. Install with: pip3 install bless"
    ) from exc


DEVICE_NAME = os.getenv("UMR_BLE_DEVICE_NAME", "UMR-Robot")
SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
WRITE_CHARACTERISTIC_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"


def on_write(characteristic: object, value: bytearray, **_: object) -> None:
    try:
        command = bytes(value).decode("utf-8", errors="replace")
    except Exception as exc:
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        print(f"[{timestamp}] Failed to decode BLE payload: {exc}")
        return

    timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    uuid = getattr(characteristic, "uuid", None)
    if uuid is not None:
        print(f"[{timestamp}] Received command on {uuid}: {command}")
    else:
        print(f"[{timestamp}] Received command: {command}")


async def main() -> None:
    server = BlessServer(name=DEVICE_NAME)
    server.write_request_func = on_write

    await server.add_new_service(SERVICE_UUID)
    await server.add_new_characteristic(
        SERVICE_UUID,
        WRITE_CHARACTERISTIC_UUID,
        GATTCharacteristicProperties.write
        | GATTCharacteristicProperties.write_without_response,
        None,
        GATTAttributePermissions.writeable,
    )

    characteristic = server.get_characteristic(WRITE_CHARACTERISTIC_UUID)
    if characteristic is None:
        raise RuntimeError("BLE characteristic was not created.")

    await server.start()

    print("BLE receiver running on Jetson Nano")
    print(f"Device name: {DEVICE_NAME}")
    print(f"Service UUID: {SERVICE_UUID}")
    print(f"Write Characteristic UUID: {WRITE_CHARACTERISTIC_UUID}")
    print("Waiting for joystick data over BLE...")

    try:
        while True:
            await asyncio.sleep(3600)
    finally:
        await server.stop()


if __name__ == "__main__":
    asyncio.run(main())
