import SwiftUI
import CoreBluetooth

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Background presets (shared: SwiftUI preview + generated CSS)

struct Preset: Identifiable {
    let id: Int
    let name: String
    let hexes: [String]
    var colors: [Color] { hexes.map { Color(hex: $0) } }
    var css: String {
        "linear-gradient(135deg," + hexes.map { "#\($0)" }.joined(separator: ",") + ")"
    }
}

let PRESETS: [Preset] = [
    .init(id: 0, name: "Aurora",  hexes: ["7c5cff", "22d3ee", "ff5ca8"]),
    .init(id: 1, name: "Sunset",  hexes: ["ff512f", "dd2476"]),
    .init(id: 2, name: "Ocean",   hexes: ["2193b0", "6dd5ed"]),
    .init(id: 3, name: "Neon",    hexes: ["00c9ff", "92fe9d"]),
    .init(id: 4, name: "Grape",   hexes: ["8e2de2", "4a00e0"]),
    .init(id: 5, name: "Fire",    hexes: ["f12711", "f5af19"]),
    .init(id: 6, name: "Mint",    hexes: ["11998e", "38ef7d"]),
    .init(id: 7, name: "Berry",   hexes: ["c31432", "240b36"]),
    .init(id: 8, name: "Sky",     hexes: ["1a2980", "26d0ce"]),
    .init(id: 9, name: "Candy",   hexes: ["fc466b", "3f5efb"]),
]

// MARK: - Portal model

struct PortalPage: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var text: String
    var bg: Int
}

enum PortalHTML {
    static func build(pages: [PortalPage], showDeviceInfo: Bool) -> String {
        let pageList = pages.isEmpty ? [PortalPage(title: "Welcome", text: "You're connected.", bg: 0)] : pages
        var css = ""
        for p in PRESETS { css += ".bg\(p.id){background:\(p.css);background-size:200% 200%;animation:g 8s ease infinite}\n" }
        var sections = ""
        for (i, pg) in pageList.enumerated() {
            let last = i == pageList.count - 1
            var body = "<h1>\(esc(pg.title))</h1><p>\(esc(pg.text))</p>"
            if showDeviceInfo && last {
                body += "<div class='lbl'>Your device</div><div class='info'>{{DEVICE}}</div>"
            }
            let btn = last
                ? "<button onclick=\"done()\">Continue</button>"
                : "<button onclick=\"go(\(i + 1))\">Next</button>"
            let back = i > 0 ? "<button class='ghost' onclick=\"go(\(i - 1))\">Back</button>" : ""
            sections += "<section class='pg bg\(pg.bg)' data-i='\(i)' style='display:\(i == 0 ? "flex" : "none")'>" +
                        "<div class='card'>\(body)<div class='nav'>\(back)\(btn)</div></div></section>\n"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>WiFi</title>
        <style>
        *{margin:0;box-sizing:border-box;font-family:-apple-system,Segoe UI,sans-serif}
        html,body{height:100%}
        @keyframes g{0%{background-position:0 50%}50%{background-position:100% 50%}100%{background-position:0 50%}}
        .pg{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;color:#fff}
        \(css)
        .card{background:rgba(0,0,0,.35);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,.2);
        border-radius:22px;padding:28px;max-width:440px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,.4)}
        h1{font-size:26px;margin-bottom:10px}p{opacity:.92;font-size:15px;line-height:1.5;white-space:pre-wrap}
        .lbl{opacity:.6;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin:16px 0 6px}
        .info{background:rgba(0,0,0,.3);border-radius:12px;padding:12px;font-size:12px;line-height:1.7;
        white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,monospace}
        .nav{display:flex;gap:10px;margin-top:20px}
        button{flex:1;padding:14px;border:0;border-radius:12px;font-size:15px;font-weight:600;color:#111;
        background:#fff;cursor:pointer}
        button.ghost{background:rgba(255,255,255,.2);color:#fff}
        </style></head><body>
        \(sections)
        <script>
        function go(n){document.querySelectorAll('.pg').forEach(function(s){s.style.display=(+s.dataset.i===n)?'flex':'none'});}
        function done(){document.body.innerHTML='<div class=pg style="display:flex"><div class=card><h1>✓ All set</h1><p>You can close this page.</p></div></div>';}
        var d="platform="+encodeURIComponent(navigator.platform||"")+"&lang="+encodeURIComponent(navigator.language||"")+"&scr="+screen.width+"x"+screen.height+"&tz="+encodeURIComponent(Intl.DateTimeFormat().resolvedOptions().timeZone||"");
        fetch("/devinfo",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:d});
        </script></body></html>
        """
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - BLE

@MainActor
final class ESP: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let svc     = CBUUID(string: "6e6b0001-b5a3-f393-e0a9-e50e24dcca9e")
    static let chSSID  = CBUUID(string: "6e6b0002-b5a3-f393-e0a9-e50e24dcca9e")
    static let chBeac  = CBUUID(string: "6e6b0003-b5a3-f393-e0a9-e50e24dcca9e")
    static let chPort  = CBUUID(string: "6e6b0004-b5a3-f393-e0a9-e50e24dcca9e")
    static let chDev   = CBUUID(string: "6e6b0005-b5a3-f393-e0a9-e50e24dcca9e")
    static let chStat  = CBUUID(string: "6e6b0006-b5a3-f393-e0a9-e50e24dcca9e")

    @Published var poweredOn = false
    @Published var scanning = false
    @Published var connected = false
    @Published var statusMsg = "Not connected"
    @Published var found: [(peripheral: CBPeripheral, name: String)] = []
    @Published var deviceInfo = "No device has connected to the WiFi yet."
    @Published var uploadPct: Double = 0

    private var central: CBCentralManager!
    private var esp: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var uploadQueue: [Data] = []
    private var uploadTotal = 0

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: nil) }

    func scan() {
        guard poweredOn else { return }
        found.removeAll()
        scanning = true
        central.scanForPeripherals(withServices: [ESP.svc])
    }

    func connect(_ p: CBPeripheral) {
        central.stopScan(); scanning = false
        esp = p; p.delegate = self
        central.connect(p)
        statusMsg = "Connecting…"
    }

    func disconnect() { if let e = esp { central.cancelPeripheralConnection(e) } }

    func setSSID(_ s: String)   { write(s, to: ESP.chSSID) }
    func setBeacon(_ s: String) { write(s, to: ESP.chBeac) }

    private func write(_ s: String, to id: CBUUID) {
        guard let e = esp, let c = chars[id], let d = s.data(using: .utf8) else { return }
        e.writeValue(d, for: c, type: .withResponse)
    }

    func uploadPortal(_ html: String) {
        guard esp != nil, chars[ESP.chPort] != nil else { return }
        var q: [Data] = [Data("B".utf8)]
        let bytes = Array(html.utf8)
        let chunk = 160
        var i = 0
        while i < bytes.count {
            let end = min(i + chunk, bytes.count)
            var d = Data("D".utf8); d.append(contentsOf: bytes[i..<end])
            q.append(d); i = end
        }
        q.append(Data("E".utf8))
        uploadQueue = q; uploadTotal = q.count; uploadPct = 0
        sendNextChunk()
    }

    private func sendNextChunk() {
        guard let e = esp, let c = chars[ESP.chPort] else { return }
        guard !uploadQueue.isEmpty else { uploadPct = 1; statusMsg = "Portal uploaded ✓"; return }
        let d = uploadQueue.removeFirst()
        uploadPct = uploadTotal == 0 ? 1 : Double(uploadTotal - uploadQueue.count) / Double(uploadTotal)
        e.writeValue(d, for: c, type: .withResponse)
    }

    // MARK: delegates
    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Task { @MainActor in poweredOn = c.state == .poweredOn; if !poweredOn { statusMsg = "Turn Bluetooth on" } }
    }
    nonisolated func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                                    advertisementData: [String: Any], rssi: NSNumber) {
        let nm = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "ESP32"
        Task { @MainActor in
            if !found.contains(where: { $0.peripheral.identifier == p.identifier }) {
                found.append((p, nm))
            }
        }
    }
    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        Task { @MainActor in statusMsg = "Discovering…" }
        p.discoverServices([ESP.svc])
    }
    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        Task { @MainActor in connected = false; statusMsg = "Disconnected"; chars.removeAll() }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == ESP.svc { p.discoverCharacteristics(nil, for: s) }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        Task { @MainActor in
            for ch in s.characteristics ?? [] {
                chars[ch.uuid] = ch
                if ch.uuid == ESP.chDev { p.setNotifyValue(true, for: ch); p.readValue(for: ch) }
                if ch.uuid == ESP.chStat { p.readValue(for: ch) }
            }
            connected = true
            statusMsg = "Connected ✓"
        }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let text = ch.value.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        Task { @MainActor in
            if ch.uuid == ESP.chDev, !text.isEmpty { deviceInfo = text }
            if ch.uuid == ESP.chStat, !text.isEmpty { statusMsg = text }
        }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == ESP.chPort { Task { @MainActor in sendNextChunk() } }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var esp = ESP()
    @State private var ssid = "FreeWiFi"
    @State private var beacon = "ESP-Beacon"
    @State private var pages: [PortalPage] = [PortalPage(title: "Welcome!", text: "Tap Next to continue.", bg: 0)]
    @State private var showDeviceInfo = true
    @State private var editing: PortalPage?

    private let bg = Color(hex: "0b0b14")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    if esp.connected {
                        apCard
                        beaconCard
                        designerCard
                        deviceCard
                    }
                }
                .padding()
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("ESP Portal")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { pg in PageEditor(page: pg) { updated in
            if let i = pages.firstIndex(where: { $0.id == updated.id }) { pages[i] = updated }
        }}
    }

    // Connection
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(esp.connected ? .green : (esp.poweredOn ? .orange : .red)).frame(width: 11, height: 11)
                Text(esp.statusMsg).font(.subheadline).foregroundStyle(.white)
                Spacer()
            }
            if !esp.connected {
                Button {
                    esp.scanning ? nil : esp.scan()
                } label: {
                    Label(esp.scanning ? "Scanning…" : "Scan for ESP32", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(gradient(0), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }.disabled(!esp.poweredOn)
                ForEach(esp.found, id: \.peripheral.identifier) { item in
                    Button { esp.connect(item.peripheral) } label: {
                        HStack { Image(systemName: "cpu"); Text(item.name); Spacer(); Image(systemName: "chevron.right") }
                            .foregroundStyle(.white).padding(12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Button(role: .destructive) { esp.disconnect() } label: {
                    Text("Disconnect").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(.red)
            }
        }
        .cardBg()
    }

    private var apCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("WiFi network name", systemImage: "wifi").font(.headline).foregroundStyle(.white)
            HStack {
                TextField("SSID", text: $ssid).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Button("Set") { esp.setSSID(ssid) }.buttonStyle(.borderedProminent).tint(Color(hex: "22d3ee"))
            }
        }.cardBg()
    }

    private var beaconCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bluetooth beacon name", systemImage: "dot.radiowaves.left.and.right").font(.headline).foregroundStyle(.white)
            HStack {
                TextField("Beacon name", text: $beacon).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Button("Set") { esp.setBeacon(beacon) }.buttonStyle(.borderedProminent).tint(Color(hex: "ff5ca8"))
            }
        }.cardBg()
    }

    private var designerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Captive portal designer", systemImage: "paintbrush.fill").font(.headline).foregroundStyle(.white)
            ForEach(pages) { pg in
                Button { editing = pg } label: {
                    HStack {
                        RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: PRESETS[pg.bg].colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 34, height: 34)
                        VStack(alignment: .leading) {
                            Text(pg.title.isEmpty ? "(untitled)" : pg.title).foregroundStyle(.white)
                            Text(PRESETS[pg.bg].name).font(.caption).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if pages.count > 1 {
                            Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                                .onTapGesture { pages.removeAll { $0.id == pg.id } }
                        }
                    }.padding(10).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Button { pages.append(PortalPage(title: "New page", text: "", bg: pages.count % PRESETS.count)) } label: {
                Label("Add page", systemImage: "plus").foregroundStyle(.white)
            }
            Toggle(isOn: $showDeviceInfo) { Text("Show device info on last page").foregroundStyle(.white) }
                .tint(Color(hex: "7c5cff"))
            Button {
                esp.uploadPortal(PortalHTML.build(pages: pages, showDeviceInfo: showDeviceInfo))
            } label: {
                Label("Push portal to ESP32", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(gradient(4), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
            }
            if esp.uploadPct > 0 && esp.uploadPct < 1 {
                ProgressView(value: esp.uploadPct).tint(Color(hex: "7c5cff"))
            }
        }.cardBg()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connected device", systemImage: "iphone.gen3").font(.headline).foregroundStyle(.white)
            Text(esp.deviceInfo)
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.cardBg()
    }

    private func gradient(_ i: Int) -> LinearGradient {
        LinearGradient(colors: PRESETS[i].colors, startPoint: .leading, endPoint: .trailing)
    }
}

private struct PageEditor: View {
    @State var page: PortalPage
    var onSave: (PortalPage) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Title", text: $page.title) }
                Section("Text") { TextEditor(text: $page.text).frame(height: 120) }
                Section("Background") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(PRESETS) { p in
                            LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white, lineWidth: page.bg == p.id ? 3 : 0))
                                .onTapGesture { page.bg = p.id }
                        }
                    }
                }
            }
            .navigationTitle("Edit page")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { onSave(page); dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct CardBg: ViewModifier {
    func body(content: Content) -> some View {
        content.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}
private extension View { func cardBg() -> some View { modifier(CardBg()) } }
