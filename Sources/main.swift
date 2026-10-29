import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

// Throwaway feasibility prototype: IDAM activation via accessibility, audio preview via AVFoundation.
// It never records to disk and deliberately never falls back to a physical microphone.
final class AudioPreview {
    private let queue = DispatchQueue(label: "local.iphone-audio.preview")
    private var session: AVCaptureSession?
    private var preview: AVCaptureAudioPreviewOutput?

    func start(device: AVCaptureDevice, volume: Float, completion: @escaping (String?) -> Void) {
        queue.async {
            self.stopOnQueue()
            do {
                let session = AVCaptureSession()
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureAudioPreviewOutput()
                output.volume = volume
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถเปิดช่องเสียงของ iPhone ได้"])
                }
                session.beginConfiguration()
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                self.session = session
                self.preview = output
                session.startRunning()
                let error = session.isRunning ? nil : "ระบบไม่เริ่มรับเสียง ลองปิด QuickTime แล้วกดเริ่มฟังอีกครั้ง"
                DispatchQueue.main.async { completion(error) }
            } catch {
                self.stopOnQueue()
                DispatchQueue.main.async { completion(error.localizedDescription) }
            }
        }
    }

    func setVolume(_ value: Float) { queue.async { self.preview?.volume = value } }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() {
        preview?.volume = 0
        session?.stopRunning()
        session = nil
        preview = nil
    }
}

enum IDAMActivator {
    static let bundleID = "com.apple.audio.AudioMIDISetup"
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func text(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    static func walk(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 16 else { return [] }
        return [root] + children(root).flatMap { walk($0, depth: depth + 1) }
    }
    static func openSetup() async throws -> NSRunningApplication {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw NSError(domain: "IDAM", code: 1, userInfo: [NSLocalizedDescriptionKey: "ไม่พบ Audio MIDI Setup"])
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
    // Only press an explicitly named Enable button in an iOS device row.
    // No screen-coordinate guesses, Disable actions, or changes to system audio defaults.
    static func pressEnable(in app: NSRunningApplication) throws -> String {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 2)
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let nodes = windows.flatMap { walk($0) }
        let rows = nodes.filter {
            text($0, kAXRoleAttribute) == kAXRowRole &&
            walk($0).contains { text($0, kAXDescriptionAttribute) == "iOS Device" }
        }
        guard rows.count == 1, let row = rows.first else {
            throw NSError(domain: "IDAM", code: rows.isEmpty ? 2 : 4, userInfo: [NSLocalizedDescriptionKey:
                rows.isEmpty ? "ยังไม่พบแถว iPhone ใน Audio MIDI Setup กรุณาเปิดหน้าต่าง Audio Devices และปลดล็อก iPhone" : "พบ iOS หลายเครื่อง กรุณาเปิด Enable ของเครื่องที่ต้องการด้วยตนเอง"])
        }
        _ = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        let enableNames = ["Enable", "เปิดใช้งาน", "เปิดใช้"]
        let buttons = walk(row).filter {
            text($0, kAXRoleAttribute) == kAXButtonRole &&
            [text($0, kAXTitleAttribute), text($0, kAXDescriptionAttribute), text($0, kAXValueAttribute)]
                .contains(where: { enableNames.contains($0) })
        }
        guard buttons.count == 1, let button = buttons.first else {
            throw NSError(domain: "IDAM", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "ไม่พบปุ่ม Enable ที่สั่งกดได้อย่างแน่นอน กรุณากด Enable ใน Audio MIDI Setup เอง แล้วกลับมากดเริ่มฟัง"])
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw NSError(domain: "IDAM", code: Int(result.rawValue), userInfo: [NSLocalizedDescriptionKey: "macOS ไม่ยอมให้กด Enable (\(result.rawValue))"])
        }
        return "ส่งคำสั่ง Enable แล้ว กำลังรออุปกรณ์เสียง…"
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var status = "เสียบ iPhone แล้วกดเชื่อมต่อ"
    @Published var deviceName = "ยังไม่พบช่องเสียง iPhone"
    @Published var volume: Double = 0.35 { didSet { audio.setVolume(Float(muted ? 0 : volume)) } }
    @Published var muted = false { didSet { audio.setVolume(Float(muted ? 0 : volume)) } }
    @Published var running = false
    @Published var busy = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var connected = false
    private let audio = AudioPreview()
    private var device: AVCaptureDevice?
    private var timer: Timer?
    private var generation = 0
    private var currentUID: String?
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "การรับเสียงหยุดทำงาน"
            Task { @MainActor in self?.stop(); self?.status = reason }
        })
    }
    func refresh() {
        trusted = AXIsProcessTrusted()
        // IDAM publishes a generic iPhone/iPad audio input. Exclude Continuity microphones.
        let matches = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.filter {
            ["iphone", "ipad"].contains($0.localizedName.lowercased()) && $0.isConnected
        }
        device = matches.count == 1 ? matches.first : nil
        connected = device != nil
        deviceName = device?.localizedName ?? (matches.count > 1 ? "พบหลายเครื่อง กรุณาเชื่อมต่อทีละเครื่อง" : "ยังไม่พบช่องเสียง iPhone")
        if running && device?.uniqueID != currentUID {
            stop()
            status = "iPhone ถูกถอดหรืออุปกรณ์เปลี่ยน เสียบใหม่แล้วกดเชื่อมต่อ"
        }
    }
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func openSetup() {
        Task {
            do { _ = try await IDAMActivator.openSetup() }
            catch { status = error.localizedDescription }
        }
    }
    func connect() {
        guard !busy else { return }
        busy = true
        generation += 1
        let attempt = generation
        Task {
            defer { if attempt == generation { busy = false } }
            refresh()
            if device == nil {
                guard trusted else {
                    status = "เปิดสิทธิ์ Accessibility เพื่อทดสอบ Enable อัตโนมัติ หรือกด Enable เองใน Audio MIDI Setup"
                    return
                }
                do {
                    let app = try await IDAMActivator.openSetup()
                    status = "กำลังรอ Audio MIDI Setup และ iPhone พร้อม…"
                    for retry in 0..<30 {
                        try await Task.sleep(for: .milliseconds(300))
                        guard attempt == generation else { return }
                        do {
                            status = try IDAMActivator.pressEnable(in: app)
                            break
                        } catch {
                            let failure = error as NSError
                            guard failure.domain == "IDAM", failure.code == 2, retry < 29 else { throw error }
                        }
                    }
                    for _ in 0..<20 {
                        try await Task.sleep(for: .milliseconds(300))
                        guard attempt == generation else { return }
                        refresh()
                        if device != nil { break }
                    }
                } catch { status = error.localizedDescription; return }
            }
            guard let input = device else { status = "ยังไม่พบช่องเสียง USB หลัง Enable กรุณาปลดล็อก iPhone แล้วลองใหม่"; return }
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard attempt == generation else { return }
            guard allowed else { status = "ต้องอนุญาต Microphone ให้แอปเพื่อรับช่องเสียง iPhone ผ่าน USB"; return }
            currentUID = input.uniqueID
            status = "กำลังเปิดเสียง iPhone…"
            audio.start(device: input, volume: Float(muted ? 0 : volume)) { [weak self] error in
                guard let self, attempt == self.generation else { return }
                self.running = error == nil
                self.status = error ?? "กำลังเปิดฟัง iPhone • เสียงออกตามอุปกรณ์ที่ Mac เลือกอยู่"
                if error == nil {
                    // IDAM remains enabled after Audio MIDI Setup quits.
                    // Leave setup open on failure so the user can troubleshoot.
                    for setup in NSRunningApplication.runningApplications(withBundleIdentifier: IDAMActivator.bundleID) {
                        _ = setup.terminate()
                    }
                }
            }
        }
    }
    func stop() {
        generation += 1
        busy = false
        audio.stop()
        running = false
        currentUID = nil
        status = "หยุดฟังแล้ว"
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "iphone.and.arrow.forward").font(.system(size: 38)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iPhone Audio").font(.largeTitle.bold())
                    Text("เสียงจาก iPhone • USB → Mac").foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.deviceName, systemImage: model.connected ? "checkmark.circle.fill" : "cable.connector")
                        .foregroundStyle(model.connected ? .green : .secondary)
                    Text(model.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.running ? "หยุดฟัง" : "เชื่อมต่อและเริ่มฟัง") {
                            if model.running { model.stop() } else { model.connect() }
                        }.buttonStyle(.borderedProminent).disabled(model.busy)
                        if model.busy { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("ตรวจอีกครั้ง") { model.refresh() }
                    }
                }.padding(8)
            }
            HStack {
                Button { model.muted.toggle() } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }.help("เปิด / ปิดเสียง iPhone")
                Slider(value: $model.volume, in: 0...1).accessibilityLabel("ระดับเสียง iPhone")
                Text("\(Int(model.volume * 100))%").monospacedDigit().frame(width: 42)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.trusted ? "Accessibility พร้อมใช้งาน" : "Enable อัตโนมัติต้องใช้ Accessibility", systemImage: model.trusted ? "checkmark.shield" : "hand.raised")
                Text("สิทธิ์นี้อนุญาตให้แอปกดปุ่ม Enable ใน Audio MIDI Setup แทนคุณ การเปิดฟังอย่างเดียวไม่ต้องใช้สิทธิ์นี้")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("เปิดการตั้งค่าสิทธิ์") { model.openSettings() }
                    Button("เปิด Audio MIDI Setup") { model.openSetup() }
                }
            }
            Text("ปิดหน้าต่างรับเสียงของ QuickTime เพื่อไม่ให้เสียงเล่นซ้อนกัน เมื่อเสียบสายใหม่ให้กดเชื่อมต่ออีกครั้ง")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(26).frame(width: 500)
    }
}

@main
struct iPhoneAudioApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("iPhone Audio") { ContentView(model: model) }
            .windowResizability(.contentSize)
        MenuBarExtra("iPhone Audio", systemImage: "iphone.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("เสียง iPhone").font(.headline)
                    Spacer()
                    Text(model.muted ? "ปิดเสียง" : "\(Int(model.volume * 100))%")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 12) {
                    Button { model.muted.toggle() } label: {
                        Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 20)
                    }.buttonStyle(.plain).accessibilityLabel(model.muted ? "เปิดเสียง iPhone" : "ปิดเสียง iPhone")
                    Slider(value: $model.volume, in: 0...1)
                        .accessibilityLabel("ระดับเสียง iPhone")
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Button(model.running ? "หยุดฟัง" : "เชื่อมต่อและเริ่มฟัง") {
                        if model.running { model.stop() } else { model.connect() }
                    }.disabled(model.busy)
                    Spacer()
                    Button("ออกจากแอป") { model.stop(); NSApplication.shared.terminate(nil) }
                }
            }.padding(16).frame(width: 320)
        }.menuBarExtraStyle(.window)
    }
}
