import SwiftUI
import WebKit
import CoreBluetooth

enum BLEConnectionState: Equatable {
    case searching
    case connecting
    case connected
    case unavailable
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

    @Published private(set) var connectionState: BLEConnectionState = .searching

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
        manager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
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

        connectedPeripheral = peripheral
        connectionState = .connecting
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
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
