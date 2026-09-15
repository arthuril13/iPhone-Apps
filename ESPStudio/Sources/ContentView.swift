import SwiftUI
import CoreBluetooth
import PhotosUI
import UIKit

// MARK: - Colour helpers

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff)/255, green: Double((v >> 8) & 0xff)/255, blue: Double(v & 0xff)/255)
    }
}

struct Preset: Identifiable { let id: Int; let name: String; let hexes: [String]
    var colors: [Color] { hexes.map { Color(hex: $0) } }
    var css: String { "linear-gradient(135deg," + hexes.map { "#\($0)" }.joined(separator: ",") + ")" }
}
let PRESETS: [Preset] = [
    .init(id:0,name:"Aurora",hexes:["7c5cff","22d3ee","ff5ca8"]), .init(id:1,name:"Sunset",hexes:["ff512f","dd2476"]),
    .init(id:2,name:"Ocean",hexes:["2193b0","6dd5ed"]), .init(id:3,name:"Neon",hexes:["00c9ff","92fe9d"]),
    .init(id:4,name:"Grape",hexes:["8e2de2","4a00e0"]), .init(id:5,name:"Fire",hexes:["f12711","f5af19"]),
    .init(id:6,name:"Mint",hexes:["11998e","38ef7d"]), .init(id:7,name:"Berry",hexes:["c31432","240b36"]),
    .init(id:8,name:"Sky",hexes:["1a2980","26d0ce"]), .init(id:9,name:"Candy",hexes:["fc466b","3f5efb"]),
]

// MARK: - Portal model

struct Block: Identifiable {
    enum Kind { case text, image }
    let id = UUID()
    var kind: Kind
    var text: String = "Your text"
    var colorHex: String = "FFFFFF"
    var glow: Bool = false
    var size: Int = 24
    var imageB64: String = ""
}

enum PortalHTML {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    static func build(blocks: [Block], bg: Int) -> String {
        var body = ""
        for b in blocks {
            switch b.kind {
            case .text:
                let glow = b.glow ? "text-shadow:0 0 14px #\(b.colorHex),0 0 26px #\(b.colorHex);" : ""
                body += "<div style='color:#\(b.colorHex);font-size:\(b.size)px;font-weight:700;margin:14px 0;\(glow)'>\(esc(b.text))</div>"
            case .image:
                if !b.imageB64.isEmpty {
                    body += "<img style='max-width:100%;border-radius:16px;margin:12px 0' src='data:image/jpeg;base64,\(b.imageB64)'>"
                }
            }
        }
        return """
        <!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
        <style>*{margin:0;box-sizing:border-box;font-family:-apple-system,Segoe UI,sans-serif}
        body{min-height:100vh;background:\(PRESETS[bg].css);background-size:200% 200%;animation:g 9s ease infinite;
        display:flex;align-items:center;justify-content:center;padding:26px}
        @keyframes g{0%{background-position:0 50%}50%{background-position:100% 50%}100%{background-position:0 50%}}
        .card{background:rgba(0,0,0,.32);backdrop-filter:blur(12px);border:1px solid rgba(255,255,255,.18);
        border-radius:22px;padding:26px;max-width:440px;width:100%;text-align:center}
        button{margin-top:18px;padding:14px 22px;border:0;border-radius:12px;font-size:16px;font-weight:700;background:#fff;color:#111}
        </style></head><body><div class='card'>\(body)
        <button onclick="document.body.innerHTML='<div class=card style=color:#fff><h2>&#10003; Done</h2></div>'">Continue</button>
        </div></body></html>
        """
    }
}

// MARK: - BLE

@MainActor
final class ESP: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let svc  = CBUUID(string: "7a2c0001-4d1e-4b6a-9b2f-2a6d7e8c9a01")
    static let cBea = CBUUID(string: "7a2c0002-4d1e-4b6a-9b2f-2a6d7e8c9a01")
    static let cWifi = CBUUID(string: "7a2c0003-4d1e-4b6a-9b2f-2a6d7e8c9a01")
    static let cPort = CBUUID(string: "7a2c0004-4d1e-4b6a-9b2f-2a6d7e8c9a01")

    @Published var poweredOn = false
    @Published var connected = false
    @Published var status = "Not connected"
    @Published var scanning = false
    @Published var uploadPct: Double = 0

    private var central: CBCentralManager!
    private var esp: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var queue: [Data] = []
    private var qTotal = 0

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: nil) }

    func scan() { guard poweredOn else { return }; scanning = true; status = "Searching…"; central.scanForPeripherals(withServices: [ESP.svc]) }
    func disconnect() { if let e = esp { central.cancelPeripheralConnection(e) } }

    func setBeacon(name: String, count: Int, on: Bool) { write("\(name)|\(count)|\(on ? 1 : 0)", ESP.cBea) }
    func setWifi(ssid: String, pass: String, portalOn: Bool) { write("\(ssid)|\(pass)|\(portalOn ? 1 : 0)", ESP.cWifi) }

    private func write(_ s: String, _ id: CBUUID) {
        guard let e = esp, let c = chars[id], let d = s.data(using: .utf8) else { return }
        e.writeValue(d, for: c, type: .withResponse)
    }

    func uploadPortal(_ html: String) {
        guard esp != nil, chars[ESP.cPort] != nil else { return }
        var q: [Data] = [Data("B".utf8)]
        let bytes = Array(html.utf8); var i = 0; let chunk = 150
        while i < bytes.count { let e = min(i+chunk, bytes.count); var d = Data("D".utf8); d.append(contentsOf: bytes[i..<e]); q.append(d); i = e }
        q.append(Data("E".utf8))
        queue = q; qTotal = q.count; uploadPct = 0.001; sendNext()
    }
    private func sendNext() {
        guard let e = esp, let c = chars[ESP.cPort] else { return }
        if queue.isEmpty { uploadPct = 1; status = "Portal sent ✓"; return }
        let d = queue.removeFirst()
        uploadPct = Double(qTotal - queue.count) / Double(qTotal)
        e.writeValue(d, for: c, type: .withResponse)
    }

    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Task { @MainActor in poweredOn = c.state == .poweredOn; if poweredOn { scan() } else { status = "Turn Bluetooth on" } }
    }
    nonisolated func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String:Any], rssi: NSNumber) {
        Task { @MainActor in status = "Found device, connecting…"; esp = p; p.delegate = self; central.stopScan(); scanning = false; central.connect(p) }
    }
    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([ESP.svc]) }
    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        Task { @MainActor in connected = false; chars.removeAll(); status = "Disconnected"; scan() }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == ESP.svc { p.discoverCharacteristics(nil, for: s) }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        Task { @MainActor in
            for ch in s.characteristics ?? [] { chars[ch.uuid] = ch }
            connected = true; status = "Connected ✓"
        }
    }
    nonisolated func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == ESP.cPort { Task { @MainActor in sendNext() } }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var esp = ESP()
    @State private var beaconName = "ESPS3"
    @State private var beaconCount = 3
    @State private var beaconOn = false
    @State private var ssid = "FreeWiFi"
    @State private var pass = ""
    @State private var portalOn = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(hex:"1b0f3a"), Color(hex:"0a1e3f"), Color(hex:"2a0f33")],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        if esp.connected {
                            beaconCard
                            wifiCard
                            NavigationLink { DesignerView(esp: esp) } label: {
                                HStack { Image(systemName: "paintbrush.pointed.fill"); Text("Design the captive portal"); Spacer(); Image(systemName: "chevron.right") }
                                    .foregroundStyle(.white).padding()
                                    .background(LinearGradient(colors: PRESETS[0].colors, startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }.padding()
                }
            }
            .navigationTitle("ESP Studio").toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle().fill(esp.connected ? .green : .orange).frame(width: 12, height: 12)
            Text(esp.status).foregroundStyle(.white)
            Spacer()
            if !esp.connected { Button { esp.scan() } label: { Image(systemName: "arrow.clockwise").foregroundStyle(.white) } }
            else { Button { esp.disconnect() } label: { Image(systemName: "xmark.circle").foregroundStyle(.white) } }
        }.glass()
    }

    private var beaconCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bluetooth Beacons", systemImage: "dot.radiowaves.left.and.right").font(.headline).foregroundStyle(.white)
            HStack { Text("Name").foregroundStyle(.white.opacity(0.7)); TextField("name", text: $beaconName).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
            Stepper("Count: \(beaconCount)", value: $beaconCount, in: 1...30).foregroundStyle(.white)
            Toggle("Broadcasting", isOn: $beaconOn).tint(Color(hex:"22d3ee")).foregroundStyle(.white)
            Button("Apply beacons") { esp.setBeacon(name: beaconName, count: beaconCount, on: beaconOn) }
                .buttonStyle(.borderedProminent).tint(Color(hex:"7c5cff"))
        }.glass()
    }

    private var wifiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("WiFi Access Point", systemImage: "wifi").font(.headline).foregroundStyle(.white)
            TextField("Network name", text: $ssid).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            SecureField("Password (blank = open)", text: $pass).textFieldStyle(.roundedBorder)
            Text("Password must be 8+ characters, or leave blank for open.").font(.caption).foregroundStyle(.white.opacity(0.5))
            Toggle("Captive portal ON", isOn: $portalOn).tint(.green).foregroundStyle(.white)
            Button("Apply WiFi") { esp.setWifi(ssid: ssid, pass: pass, portalOn: portalOn) }
                .buttonStyle(.borderedProminent).tint(Color(hex:"22d3ee"))
        }.glass()
    }
}

// MARK: - Portal designer

struct DesignerView: View {
    @ObservedObject var esp: ESP
    @State private var blocks: [Block] = [Block(kind: .text, text: "Welcome!", colorHex: "FFFFFF", glow: true, size: 34)]
    @State private var bg = 0
    @State private var editing: Block?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            LinearGradient(colors: PRESETS[bg].colors, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea().opacity(0.35)
            ScrollView {
                VStack(spacing: 14) {
                    // background picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Background").font(.headline).foregroundStyle(.white)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(PRESETS) { p in
                                    LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: bg == p.id ? 3 : 0))
                                        .onTapGesture { bg = p.id }
                                }
                            }
                        }
                    }.glass()

                    // blocks
                    ForEach(blocks) { b in
                        Button { if b.kind == .text { editing = b } } label: {
                            HStack {
                                Image(systemName: b.kind == .text ? "textformat" : "photo")
                                Text(b.kind == .text ? b.text : "Image").lineLimit(1)
                                Spacer()
                                Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                                    .onTapGesture { blocks.removeAll { $0.id == b.id } }
                            }.foregroundStyle(.white).padding()
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    HStack {
                        Button { blocks.append(Block(kind: .text)) } label: { Label("Text", systemImage: "plus").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(.white)
                        PhotosPicker(selection: $pickerItem, matching: .images) { Label("Image", systemImage: "photo").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(.white)
                    }

                    Button { esp.uploadPortal(PortalHTML.build(blocks: blocks, bg: bg)) } label: {
                        Label("Push portal to device", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(LinearGradient(colors: PRESETS[4].colors, startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    if esp.uploadPct > 0 && esp.uploadPct < 1 { ProgressView(value: esp.uploadPct).tint(.white) }
                }.padding()
            }
        }
        .navigationTitle("Portal Designer").preferredColorScheme(.dark)
        .sheet(item: $editing) { blk in TextEditorSheet(block: blk) { upd in if let i = blocks.firstIndex(where: { $0.id == upd.id }) { blocks[i] = upd } } }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let b64 = downscaleB64(data) {
                    blocks.append(Block(kind: .image, imageB64: b64))
                }
                pickerItem = nil
            }
        }
    }

    private func downscaleB64(_ data: Data) -> String? {
        guard let ui = UIImage(data: data) else { return nil }
        let maxW: CGFloat = 380
        let scale = min(1, maxW / max(ui.size.width, 1))
        let sz = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let img = UIGraphicsImageRenderer(size: sz).image { _ in ui.draw(in: CGRect(origin: .zero, size: sz)) }
        return img.jpegData(compressionQuality: 0.45)?.base64EncodedString()
    }
}

struct TextEditorSheet: View {
    @State var block: Block
    var onSave: (Block) -> Void
    @Environment(\.dismiss) private var dismiss
    let swatches = ["FFFFFF","FF5CA8","22D3EE","7C5CFF","34E89E","FFD166","FF6B6B","F5AF19"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Text") { TextField("Text", text: $block.text) }
                Section("Size") { Stepper("\(block.size)px", value: $block.size, in: 12...60, step: 2) }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(swatches, id: \.self) { hx in
                            Circle().fill(Color(hex: hx)).frame(height: 40)
                                .overlay(Circle().stroke(.primary, lineWidth: block.colorHex == hx ? 3 : 0))
                                .onTapGesture { block.colorHex = hx }
                        }
                    }
                }
                Section { Toggle("Glow effect", isOn: $block.glow) }
            }
            .navigationTitle("Edit text")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { onSave(block); dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private struct Glass: ViewModifier {
    func body(content: Content) -> some View {
        content.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
private extension View { func glass() -> some View { modifier(Glass()) } }
