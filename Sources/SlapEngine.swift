import Foundation
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum DetectionMode: String, CaseIterable, Identifiable {
    case auto, acelerometro, microfone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automático"
        case .acelerometro: return "Acelerômetro"
        case .microfone: return "Microfone"
        }
    }
}

@MainActor
final class SlapEngine: ObservableObject {
    static let shared = SlapEngine()
    private let defaults = UserDefaults.standard

    // MARK: Configurações persistidas
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); restartDetection() } }
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: "sensitivity"); applyThresholds() } }
    @Published var cooldown: Double { didSet { defaults.set(cooldown, forKey: "cooldown") } }
    @Published var pack: SoundPack { didSet { defaults.set(pack.rawValue, forKey: "pack") } }
    @Published var mode: DetectionMode { didSet { defaults.set(mode.rawValue, forKey: "mode"); restartDetection() } }
    @Published var scaleVolume: Bool { didSet { defaults.set(scaleVolume, forKey: "scaleVolume") } }
    @Published var totalSlaps: Int { didSet { defaults.set(totalSlaps, forKey: "totalSlaps") } }
    @Published var strongest: Double { didSet { defaults.set(strongest, forKey: "strongest") } }

    // MARK: Estado ao vivo
    @Published var liveLevel: Double = 0
    @Published var lastForce: Double = 0
    @Published var justSlapped = false
    @Published var sensorStatus = "Parado"
    @Published var activeSensor: DetectionMode? = nil
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    /// O medidor só atualiza com o painel aberto, para economizar CPU.
    var panelVisible = false { didSet { if !panelVisible { liveLevel = 0 } } }

    private let accel = AccelerometerDetector()
    private let mic = MicrophoneDetector()
    private let sound = SoundPlayer()

    private var lastSlapTime: TimeInterval = 0
    private var streak = 0
    private var resetIconWork: DispatchWorkItem?

    private init() {
        defaults.register(defaults: [
            "enabled": true, "sensitivity": 0.55, "cooldown": 0.6,
            "pack": SoundPack.whatsapp.rawValue, "mode": DetectionMode.auto.rawValue,
            "scaleVolume": true, "totalSlaps": 0, "strongest": 0.0,
        ])
        enabled = defaults.bool(forKey: "enabled")
        sensitivity = defaults.double(forKey: "sensitivity")
        cooldown = defaults.double(forKey: "cooldown")
        pack = SoundPack(rawValue: defaults.string(forKey: "pack") ?? "") ?? .whatsapp
        mode = DetectionMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .auto
        scaleVolume = defaults.bool(forKey: "scaleVolume")
        totalSlaps = defaults.integer(forKey: "totalSlaps")
        strongest = defaults.double(forKey: "strongest")

        accel.onImpact = { [weak self] peak in
            Task { @MainActor in self?.impact(raw: peak, from: .acelerometro) }
        }
        accel.onLevel = { [weak self] lvl in
            Task { @MainActor in if let s = self, s.panelVisible, s.activeSensor == .acelerometro { s.liveLevel = lvl } }
        }
        mic.onImpact = { [weak self] peak in
            Task { @MainActor in self?.impact(raw: peak, from: .microfone) }
        }
        mic.onLevel = { [weak self] lvl in
            Task { @MainActor in if let s = self, s.panelVisible, s.activeSensor == .microfone { s.liveLevel = lvl } }
        }
        applyThresholds()
        restartDetection()
        refreshCustomSounds()

        // Modo de teste: `SlapMac --test-slap` simula tapas ao abrir.
        if CommandLine.arguments.contains("--test-slap") {
            for (i, f) in [1.3, 2.5, 5.0].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 2.0) { [weak self] in
                    self?.lastSlapTime = 0
                    self?.slap(force: f)
                    NSLog("SlapMac: tapa de teste força \(f)")
                }
            }
        }
    }

    // MARK: Limiares

    /// Limiar do acelerômetro em g (escala logarítmica: 0,8 g … 0,05 g).
    var accelThreshold: Double { 0.8 * pow(0.05 / 0.8, sensitivity) }
    /// Limiar do microfone em amplitude (0,95 … 0,12).
    var micThreshold: Double { 0.95 - 0.83 * sensitivity }

    var currentThreshold: Double {
        activeSensor == .microfone ? micThreshold : accelThreshold
    }

    private func applyThresholds() {
        accel.threshold = accelThreshold
        mic.threshold = micThreshold
    }

    // MARK: Detecção

    func restartDetection() {
        accel.stop()
        mic.stop()
        activeSensor = nil
        liveLevel = 0
        guard enabled else { sensorStatus = "Pausado"; return }

        if mode != .microfone {
            if accel.start() {
                activeSensor = .acelerometro
                sensorStatus = "Acelerômetro ativo"
                return
            }
            if mode == .acelerometro {
                sensorStatus = "Acelerômetro indisponível neste Mac"
                return
            }
        }
        sensorStatus = "Pedindo acesso ao microfone…"
        MicrophoneDetector.requestPermission { [weak self] ok in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                if ok && self.mic.start() {
                    self.activeSensor = .microfone
                    self.sensorStatus = "Microfone ativo"
                } else {
                    self.sensorStatus = "Sem acesso ao microfone"
                }
            }
        }
    }

    private func impact(raw: Double, from sensor: DetectionMode) {
        guard enabled, sensor == activeSensor else { return }
        let threshold = sensor == .microfone ? micThreshold : accelThreshold
        slap(force: raw / threshold)
    }

    /// force = quantas vezes acima do limiar (>= 1).
    func slap(force: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSlapTime >= cooldown else { return }
        streak = (now - lastSlapTime < cooldown + 2.0) ? streak + 1 : 1
        lastSlapTime = now

        totalSlaps += 1
        lastForce = force
        if force > strongest { strongest = force }

        let volume: Float = scaleVolume ? Float(min(1.0, 0.35 + 0.65 * min((force - 1) / 4, 1))) : 1.0
        sound.play(pack: pack, force: force, volume: max(volume, 0.35), streak: streak)

        justSlapped = true
        resetIconWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.justSlapped = false }
        resetIconWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func testSlap() {
        lastSlapTime = 0
        slap(force: Double.random(in: 1.2...5.5))
    }

    func resetStats() {
        totalSlaps = 0
        strongest = 0
        lastForce = 0
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("SlapMac: falha ao alterar login: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openCustomFolder() {
        NSWorkspace.shared.open(SoundPlayer.customFolder)
    }

    @Published var customSounds: [URL] = []

    func refreshCustomSounds() {
        customSounds = sound.customFiles().sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Abre o seletor de arquivos e copia os áudios escolhidos para a pasta do app.
    func importAudio() {
        let panel = NSOpenPanel()
        panel.title = "Importar áudio para o SlapMac"
        panel.prompt = "Importar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self else { return }
                let folder = SoundPlayer.customFolder
                var imported = 0
                for url in panel.urls {
                    var dest = folder.appendingPathComponent(url.lastPathComponent)
                    var n = 2
                    while FileManager.default.fileExists(atPath: dest.path) {
                        let base = url.deletingPathExtension().lastPathComponent
                        dest = folder.appendingPathComponent("\(base) \(n).\(url.pathExtension)")
                        n += 1
                    }
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { imported += 1 }
                }
                self.refreshCustomSounds()
                if imported > 0 { self.pack = .personalizado }
            }
        }
    }

    func removeCustomSound(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshCustomSounds()
    }

    func preview(_ url: URL) {
        sound.playFile(url)
    }

    func quit() {
        accel.stop()
        mic.stop()
        NSApp.terminate(nil)
    }
}
