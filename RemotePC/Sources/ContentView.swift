import SwiftUI
import UIKit

// MARK: - Networking

@MainActor
final class PCClient: ObservableObject {
    @Published var online = false
    @Published var statusText = "Not connected"
    @Published var output = ""
    @Published var screen: UIImage?
    @Published var camera: UIImage?
    @Published var toast: String?

    private var defaults = UserDefaults.standard
    var host: String { (defaults.string(forKey: "host") ?? "").trimmingCharacters(in: .whitespaces) }
    var pin: String { defaults.string(forKey: "pin") ?? "" }

    private func request(_ path: String, method: String = "GET", json: [String: Any]? = nil) -> URLRequest? {
        var h = host
        if !h.isEmpty, !h.hasPrefix("http") { h = "http://" + h }
        guard let url = URL(string: h + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 15
        r.setValue(pin, forHTTPHeaderField: "X-PIN")
        if let json {
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func flash(_ msg: String) {
        toast = msg
        Task { try? await Task.sleep(nanoseconds: 2_200_000_000); if toast == msg { toast = nil } }
    }

    // Ping /api/status to know if we're connected and authorised.
    func checkStatus() async {
        guard !host.isEmpty else { statusText = "Set your PC address in Settings"; online = false; return }
        guard let req = request("/api/status") else { statusText = "Bad address"; online = false; return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { statusText = "Wrong PIN"; online = false; return }
            if code != 200 { statusText = "PC responded \(code)"; online = false; return }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let host = obj["hostname"] as? String ?? "PC"
                statusText = "Connected to \(host)"
            } else {
                statusText = "Connected"
            }
            online = true
        } catch {
            statusText = "Can't reach PC"
            online = false
        }
    }

    func power(_ action: String) async {
        await post("/api/power/\(action)", label: action.capitalized)
    }

    func media(_ action: String) async {
        await post("/api/media/\(action)", label: nil)
    }

    private func post(_ path: String, label: String?) async {
        guard let req = request(path, method: "POST") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { flash("Wrong PIN"); return }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["message"] as? String {
                flash(msg)
            } else if let label {
                flash(label)
            }
        } catch {
            flash("Failed - is the PC on?")
        }
    }

    func run(_ command: String) async {
        guard !command.isEmpty else { return }
        output = "Running..."
        guard let req = request("/api/run", method: "POST", json: ["command": command]) else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { output = "Wrong PIN"; return }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let out = obj["output"] as? String {
                output = out
            } else {
                output = String(data: data, encoding: .utf8) ?? "(no output)"
            }
        } catch {
            output = "Failed to run - is the PC reachable?"
        }
    }

    // Fetch one JPEG frame for either the screen or the camera.
    func fetchImage(_ path: String) async -> UIImage? {
        guard let req = request(path) else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        } catch { return nil }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var pc = PCClient()
    @AppStorage("host") private var host = ""
    @AppStorage("pin") private var pin = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    StatusCard(pc: pc)
                    PowerCard(pc: pc)
                    MediaCard(pc: pc)
                    ScreenCard(pc: pc)
                    CameraCard(pc: pc)
                    CommandCard(pc: pc)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("RemotePC")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .overlay(alignment: .bottom) {
                if let t = pc.toast {
                    Text(t)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: pc.toast)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .task { await pc.checkStatus() }
        .onAppear { if host.isEmpty { showSettings = true } }
    }
}

// MARK: - Cards

struct StatusCard: View {
    @ObservedObject var pc: PCClient
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(pc.online ? .green : .red).frame(width: 12, height: 12)
            Text(pc.statusText).font(.subheadline)
            Spacer()
            Button { Task { await pc.checkStatus() } } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .cardStyle()
    }
}

struct PowerCard: View {
    @ObservedObject var pc: PCClient
    @State private var confirm: String?

    let items: [(String, String, String, Color)] = [
        ("lock", "Lock", "lock.fill", .blue),
        ("sleep", "Sleep", "moon.fill", .indigo),
        ("restart", "Restart", "arrow.triangle.2.circlepath", .orange),
        ("shutdown", "Shut Down", "power", .red),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Power", systemImage: "bolt.fill").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(items, id: \.0) { key, title, icon, color in
                    Button {
                        if key == "restart" || key == "shutdown" { confirm = key }
                        else { Task { await pc.power(key) } }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: icon).font(.title2)
                            Text(title).font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(color, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            Button(role: .destructive) { Task { await pc.power("cancel") } } label: {
                Text("Cancel pending restart/shutdown").font(.footnote)
            }
        }
        .cardStyle()
        .alert("Are you sure?", isPresented: .constant(confirm != nil)) {
            Button("Cancel", role: .cancel) { confirm = nil }
            Button(confirm == "shutdown" ? "Shut Down" : "Restart", role: .destructive) {
                if let c = confirm { Task { await pc.power(c) } }
                confirm = nil
            }
        } message: {
            Text(confirm == "shutdown" ? "This shuts the PC down in 10 seconds." : "This restarts the PC in 10 seconds.")
        }
    }
}

struct MediaCard: View {
    @ObservedObject var pc: PCClient
    let items: [(String, String)] = [
        ("voldown", "speaker.wave.1"), ("mute", "speaker.slash.fill"), ("volup", "speaker.wave.3"),
        ("prev", "backward.fill"), ("playpause", "playpause.fill"), ("next", "forward.fill"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Media & Volume", systemImage: "speaker.wave.2.fill").font(.headline)
            HStack(spacing: 10) {
                ForEach(items, id: \.0) { key, icon in
                    Button { Task { await pc.media(key) } } label: {
                        Image(systemName: icon).font(.title3)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .cardStyle()
    }
}

struct ScreenCard: View {
    @ObservedObject var pc: PCClient
    @State private var live = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Screen", systemImage: "display").font(.headline)
                Spacer()
                Toggle("Live", isOn: $live).labelsHidden()
            }
            Group {
                if let img = pc.screen {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                        .frame(height: 150)
                        .overlay(Text("Tap refresh to view the screen").font(.footnote).foregroundStyle(.secondary))
                }
            }
            Button { Task { pc.screen = await pc.fetchImage("/api/screen.jpg?scale=0.6") } } label: {
                Label("Refresh screenshot", systemImage: "camera.viewfinder")
            }
        }
        .cardStyle()
        .onChange(of: live) { on in
            task?.cancel()
            if on {
                task = Task {
                    while !Task.isCancelled {
                        if let img = await pc.fetchImage("/api/screen.jpg?scale=0.6") { pc.screen = img }
                        try? await Task.sleep(nanoseconds: 700_000_000)
                    }
                }
            }
        }
        .onDisappear { task?.cancel() }
    }
}

struct CameraCard: View {
    @ObservedObject var pc: PCClient
    @State private var live = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PC Camera", systemImage: "web.camera").font(.headline)
                Spacer()
                Toggle("Live", isOn: $live).labelsHidden()
            }
            Group {
                if let img = pc.camera {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                        .frame(height: 150)
                        .overlay(Text("Needs opencv-python on the PC").font(.footnote).foregroundStyle(.secondary))
                }
            }
        }
        .cardStyle()
        .onChange(of: live) { on in
            task?.cancel()
            if on {
                task = Task {
                    while !Task.isCancelled {
                        if let img = await pc.fetchImage("/api/camera.jpg?scale=0.6") { pc.camera = img }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
        }
        .onDisappear { task?.cancel() }
    }
}

struct CommandCard: View {
    @ObservedObject var pc: PCClient
    @State private var command = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Run PowerShell", systemImage: "terminal.fill").font(.headline)
            HStack {
                TextField("e.g. Get-Date", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Run") { let c = command; Task { await pc.run(c) } }
                    .buttonStyle(.borderedProminent)
            }
            if !pc.output.isEmpty {
                ScrollView {
                    Text(pc.output).font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardStyle()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("host") private var host = ""
    @AppStorage("pin") private var pin = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("PC address") {
                    TextField("192.168.1.50:8090 or Tailscale IP", text: $host)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Text("Include the port (8090). http:// is added automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("PIN") {
                    SecureField("PIN from the PC", text: $pin)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Style

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
private extension View { func cardStyle() -> some View { modifier(CardStyle()) } }
