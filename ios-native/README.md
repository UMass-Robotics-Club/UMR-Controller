# UMR Remote iOS App

This folder wraps your existing web controller (`index.html`, `styles.css`, `app.js`) in a native iOS app using `WKWebView`.

The transport is now Bluetooth Low Energy (BLE), not Wi-Fi/UDP.
The iOS app acts as a BLE central and sends joystick commands to a Jetson Nano BLE peripheral.

## BLE UUIDs Used

- Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- Write Characteristic UUID: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`

These UUIDs must match on iOS and Jetson.

## 1) Generate Xcode Project

Install XcodeGen if you do not already have it:

```bash
brew install xcodegen
```

Generate the Xcode project:

```bash
cd ios-native
xcodegen generate
```

This creates `UMRRemote.xcodeproj`.

## 2) Start The BLE Receiver

For local testing, you can run the receiver on your Mac now and later move the same script to the Jetson unchanged.

On the machine that will act as the robot:

```bash
cd /path/to/UMR\ Remote\ Controller
python3 -m pip install bless
python3 laptop_receiver.py
```

If you want the device to advertise a custom name, set `UMR_BLE_DEVICE_NAME` first.

You should see logs that the BLE service is running and waiting for commands.

## 3) Run On A Physical iPhone

BLE central/peripheral testing must be done on a real iPhone, not the iOS simulator.

1. Open `ios-native/UMRRemote.xcodeproj` in Xcode.
2. Select your connected iPhone as the run destination.
3. Press Run.
4. Accept Bluetooth permission when prompted.

The app will auto-scan for the Jetson BLE service and begin writing commands.

## 4) Keep Web Files in Sync

The app loads bundled files from `ios-native/UMRRemote/Web`.

After changing root web files, sync them:

```bash
cd ios-native
./sync-web-assets.sh
```

Then run the app again in Xcode.

## 5) Deploy Directly To A Connected iPhone

If Xcode shows intermittent sandbox-extension errors while running from the UI,
you can deploy from terminal with a stable path:

```bash
cd ios-native
./deploy-to-iphone.sh
```

This script builds a signed Debug app, installs it to the connected device, and launches it.
