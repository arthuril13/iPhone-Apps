import SwiftUI
import CoreBluetooth

// MARK: - Beacon engine

@MainActor
final class BeaconManager: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published var poweredOn = false
    @Published var broadcasting = false
    @Published var currentName = ""
    @Published var cycle = 0            // how many name-changes we've pushed out

    private var manager: CBPeripheralManager?
    private var names: [String] = []
    private var index = 0
    private var interval: TimeInterval = 0.8
    private var timer: Timer?
    // One arbitrary service UUID so the advert is well-formed.
    private let serviceUUID = CBUUID(string: "FEED")

    func boot() {
        if manager == nil {
            // Creating this triggers the Bluetooth permission prompt.
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }
    }

    func start(names: [String], interval: TimeInterval) {
        guard let manager, manager.state == .poweredOn, !names.isEmpty else { return }
        self.names = names
        self.interval = max(0.3, interval)
        index = 0
        cycle = 0
        broadcasting = true
        advertiseCurrent()
        timer?.invalidate()
        if names.count > 1 {
            timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.broadcasting else { return }
                    self.index = (self.index + 1) % self.names.count
                    self.advertiseCurrent()
                }
            }
        }
    }

    private func advertiseCurrent() {
        guard let manager else { return }
        manager.stopAdvertising()
        let name = names[index]
        currentName = name
        cycle += 1
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: name,
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
        ])
    }

    func stop() {
        timer?.invalidate(); timer = nil
        manager?.stopAdvertising()
        broadcasting = false
        currentName = ""
    }

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let on = peripheral.state == .poweredOn
        Task { @MainActor in
            self.poweredOn = on
            if !on { self.stop() }
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var beacon = BeaconManager()
    @State private var baseName = "AirPods"
    @State private var count = 3
    @State private var interval = 0.8

    private var names: [String] {
        count <= 1 ? [baseName] : (1...count).map { "\(baseName) \($0)" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    liveCard
                    settingsCard
                    button
                    infoCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("BLE Beacon")
        }
        .onAppear { beacon.boot() }
    }

    private var liveCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(beacon.broadcasting ? Color.blue.opacity(0.25) : Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 130, height: 130)
                if beacon.broadcasting {
                    Circle()
                        .stroke(Color.blue.opacity(0.5), lineWidth: 3)
                        .frame(width: 130, height: 130)
                        .scaleEffect(1.0 + Double(beacon.cycle % 2) * 0.25)
                        .opacity(beacon.cycle % 2 == 0 ? 0.8 : 0.2)
                        .animation(.easeOut(duration: 0.6), value: beacon.cycle)
                }
                Image(systemName: beacon.broadcasting ? "dot.radiowaves.left.and.right" : "wave.3.right")
                    .font(.system(size: 44))
                    .foregroundStyle(beacon.broadcasting ? .blue : .secondary)
            }
            Text(beacon.broadcasting ? beacon.currentName : "Not broadcasting")
                .font(.title3.weight(.semibold))
                .animation(.default, value: beacon.currentName)
            if beacon.broadcasting {
                Text("broadcast #\(beacon.cycle)")
                    .font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Beacon name").font(.subheadline.weight(.medium))
                TextField("Name", text: $baseName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(beacon.broadcasting)
            }
            Stepper("Number of beacons: \(count)", value: $count, in: 1...30)
                .disabled(beacon.broadcasting)
            VStack(alignment: .leading, spacing: 6) {
                Text("Switch speed: \(String(format: "%.1f", interval))s")
                    .font(.subheadline.weight(.medium))
                Slider(value: $interval, in: 0.3...3.0, step: 0.1)
                    .disabled(beacon.broadcasting)
            }
            if count > 1 {
                Text("Cycles through: " + names.prefix(3).joined(separator: ", ") + (count > 3 ? "…" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var button: some View {
        Button {
            if beacon.broadcasting { beacon.stop() }
            else { beacon.start(names: names, interval: interval) }
        } label: {
            Text(beacon.broadcasting ? "Stop" : "Start broadcasting")
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(beacon.broadcasting ? Color.red : (beacon.poweredOn ? Color.blue : Color.gray),
                            in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!beacon.poweredOn && !beacon.broadcasting)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(beacon.poweredOn ? "Bluetooth ready" : "Turn Bluetooth on",
                  systemImage: beacon.poweredOn ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(beacon.poweredOn ? .green : .orange)
            Text("iOS broadcasts one advert at a time, so multiple beacons are shown by rotating the name. Keep this app open — iOS hides the name when it's in the background. Broadcast-only: it can't connect to or control anything.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
private extension View { func cardStyle() -> some View { modifier(CardStyle()) } }
