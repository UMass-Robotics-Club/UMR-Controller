import SwiftUI
import WebKit
import CoreBluetooth

enum BLEConnectionState: Equatable {
    case searching
    case connecting
    case connected
    case unavailable
}

struct DiscoveredRobot: Identifiable, Equatable {
    let id: UUID
    let name: String
}

final class BLECommandBridge: NSObject, ObservableObject {
    static let shared = BLECommandBridge()

    // Must match the Jetson BLE service/characteristic UUIDs.
    private static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let writeCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var pendingPayload: Data?
    private var hasStarted = false
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var advertisedNames: [UUID: String] = [:]

    @Published private(set) var connectionState: BLEConnectionState = .searching
    @Published private(set) var discoveredRobots: [DiscoveredRobot] = []
    @Published private(set) var connectedRobotName: String?

    private override init() {
        super.init()
    }

    func send(payload: String) {
        DispatchQueue.main.async {
            self.startIfNeeded()
            self.pendingPayload = Data(payload.utf8)
            self.flushIfPossible()
        }
    }

    func start() {
        DispatchQueue.main.async {
            self.startIfNeeded()
        }
    }

    /// Connect to a robot the user picked from the list.
    func connect(to robot: DiscoveredRobot) {
        DispatchQueue.main.async {
            guard let manager = self.centralManager,
                  self.connectedPeripheral == nil,
                  let peripheral = self.discoveredPeripherals[robot.id] else {
                return
            }

            self.connectedPeripheral = peripheral
            self.connectedRobotName = robot.name
            self.connectionState = .connecting
            manager.stopScan()
            peripheral.delegate = self
            manager.connect(peripheral, options: nil)
        }
    }

    /// Clear the list and scan again.
    func rescan() {
        DispatchQueue.main.async {
            guard self.connectedPeripheral == nil else {
                return
            }

            self.centralManager?.stopScan()
            self.startScan()
        }
    }

    private func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        connectionState = .searching
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    private func startScan() {
        guard let manager = centralManager, manager.state == .poweredOn else {
            connectionState = .unavailable
            return
        }

        connectionState = .searching
        discoveredPeripherals = [:]
        advertisedNames = [:]
        discoveredRobots = []
        // Duplicates on so the scan response (which carries the robot name) is seen too
        manager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func flushIfPossible() {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic,
              let payload = pendingPayload else {
            return
        }

        let supportsWriteWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
        let supportsWriteWithResponse = characteristic.properties.contains(.write)

        if supportsWriteWithoutResponse {
            peripheral.writeValue(payload, for: characteristic, type: .withoutResponse)
            pendingPayload = nil
            return
        }

        if supportsWriteWithResponse {
            peripheral.writeValue(payload, for: characteristic, type: .withResponse)
            pendingPayload = nil
        }
    }
}

extension BLECommandBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        } else {
            connectionState = .unavailable
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        if connectedPeripheral != nil {
            return
        }

        // Prefer the advertised name; peripheral.name is the host's cached device name.
        // The advertised name can arrive in a later packet, so remember it once seen.
        if let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           !advertisedName.isEmpty {
            advertisedNames[peripheral.identifier] = advertisedName
        }

        let name = advertisedNames[peripheral.identifier]
            ?? peripheral.name
            ?? "Unknown robot"

        discoveredPeripherals[peripheral.identifier] = peripheral
        let robot = DiscoveredRobot(id: peripheral.identifier, name: name)

        if let index = discoveredRobots.firstIndex(where: { $0.id == robot.id }) {
            if discoveredRobots[index] != robot {
                discoveredRobots[index] = robot
                discoveredRobots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } else {
            discoveredRobots.append(robot)
            discoveredRobots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectedPeripheral = nil
        connectedRobotName = nil
        writeCharacteristic = nil
        startScan()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
            connectedRobotName = nil
            writeCharacteristic = nil
        }

        connectionState = .searching
        startScan()
    }
}

extension BLECommandBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard error == nil,
              let services = peripheral.services else {
            return
        }

        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.writeCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil,
              let characteristics = service.characteristics else {
            return
        }

        for characteristic in characteristics where characteristic.uuid == Self.writeCharacteristicUUID {
            writeCharacteristic = characteristic
            flushIfPossible()
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if error == nil {
            flushIfPossible()
        }
    }
}

#if os(iOS)
struct WebContainerView: UIViewRepresentable {
    final class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "remoteBLE",
                  let body = message.body as? [String: Any],
                  let payload = body["payload"] as? String else {
                return
            }

            BLECommandBridge.shared.send(payload: payload)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "remoteBLE")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web"),
           let webRoot = Bundle.main.url(forResource: "Web", withExtension: nil) {
            webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
        } else if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            // Fallback when resources are copied to bundle root instead of Web/.
            webView.loadFileURL(indexURL, allowingReadAccessTo: Bundle.main.bundleURL)
        } else {
            let html = "<html><body style='background:black;color:white;font-family:-apple-system'>index.html was not found in app bundle.</body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}
#else
struct WebContainerView: View {
    var body: some View {
        Text("This app requires iOS.")
            .foregroundStyle(.white)
            .padding()
            .background(Color.black)
    }
}
#endif
