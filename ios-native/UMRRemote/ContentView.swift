import SwiftUI

struct ContentView: View {
    @ObservedObject private var bleBridge = BLECommandBridge.shared

    var body: some View {
        ZStack {
            if bleBridge.connectionState == .connected {
                WebContainerView()
                    .ignoresSafeArea()
                    .background(Color.black)
                    .transition(.opacity)
            } else {
                connectionView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: bleBridge.connectionState)
        .onAppear {
            bleBridge.start()
        }
    }

    private var connectionView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.02, green: 0.02, blue: 0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)

                Text(statusTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(statusMessage)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if bleBridge.connectionState == .unavailable {
                    Text("Make sure Bluetooth is on and the robot or Mac receiver is advertising the BLE service.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }
            .padding(28)
        }
    }

    private var statusTitle: String {
        switch bleBridge.connectionState {
        case .searching:
            return "Searching for Robot"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .unavailable:
            return "Bluetooth Unavailable"
        }
    }

    private var statusMessage: String {
        switch bleBridge.connectionState {
        case .searching:
            return "Looking for your Mac test host or Jetson robot over Bluetooth Low Energy."
        case .connecting:
            return "Found a device. Finishing the BLE handshake now."
        case .connected:
            return ""
        case .unavailable:
            return "Turn on Bluetooth, then open the receiver on your Mac or robot so the app can connect."
        }
    }
}

#Preview {
    ContentView()
}
