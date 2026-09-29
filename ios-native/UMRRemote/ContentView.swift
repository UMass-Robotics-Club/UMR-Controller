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
                if bleBridge.connectionState != .searching || bleBridge.discoveredRobots.isEmpty {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }

                Text(statusTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(statusMessage)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if bleBridge.connectionState == .searching {
                    robotList
                }

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

    private var robotList: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(bleBridge.discoveredRobots) { robot in
                        Button {
                            bleBridge.connect(to: robot)
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text(robot.name)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .frame(maxWidth: 420, maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)

            Button("Scan again") {
                bleBridge.rescan()
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var statusTitle: String {
        switch bleBridge.connectionState {
        case .searching:
            return bleBridge.discoveredRobots.isEmpty ? "Searching for Robots" : "Choose a Robot"
        case .connecting:
            return "Connecting to \(bleBridge.connectedRobotName ?? "Robot")"
        case .connected:
            return "Connected"
        case .unavailable:
            return "Bluetooth Unavailable"
        }
    }

    private var statusMessage: String {
        switch bleBridge.connectionState {
        case .searching:
            return bleBridge.discoveredRobots.isEmpty
                ? "Looking for robots nearby over Bluetooth Low Energy."
                : "Tap the robot you want to control."
        case .connecting:
            return "Finishing the BLE handshake now."
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
