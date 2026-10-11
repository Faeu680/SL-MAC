import Foundation
import AppKit
import AVFoundation

enum SoundPack: String, CaseIterable, Identifiable {
    case whatsapp, miau, gemidos, voz, cartoon, sistema, personalizado
    var id: String { rawValue }
    var title: String {
        switch self {
        case .whatsapp: return "Botão do WhatsApp"
        case .miau: return "Miau + Rizz"
        case .gemidos: return "Gemidos"
        case .voz: return "Voz (gritos)"
        case .cartoon: return "Desenho animado"
        case .sistema: return "Sons do macOS"
        case .personalizado: return "Personalizado"
        }
    }
}

enum SlapStrength {
    case leve, medio, forte
    init(force: Double) {
        if force < 1.8 { self = .leve } else if force < 3.5 { self = .medio } else { self = .forte }
    }
}

final class SoundPlayer: NSObject {
    static var customFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("SlapMac/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let customPlayer = AVAudioPlayerNode()
    private let pitchUnit = AVAudioUnitTimePitch()
    private let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private var bufferCache: [URL: AVAudioPCMBuffer] = [:]
    private var lastWasRizz = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var activeSounds: [NSSound] = []
    private var lastPhrase: String?

    private let leve = ["Ai!", "Ui!", "Ei!", "Opa!", "Ai, ai.", "Hmpf!"]
    private let medio = ["Ai! Isso dói!", "Ei, para com isso!", "Ui, que tapa!", "Ai ai ai ai!", "Ô, calma aí!", "Ai! Por quê?"]
    private let forte = ["AAAAAI! Tá maluco?!", "Socorro! Tão me batendo!", "Ai! Eu sou um computador caro!", "Para! Vou chamar a Apple!", "AAAAH! Minha tela!", "Ai! Isso vai deixar marca!"]
    private let combo = ["Chega! Chega! Chega!", "Você tem algum problema comigo?", "Eu vou travar de propósito, hein!", "Tá bom, tá bom, eu salvo o arquivo!", "Socorro, alguém me ajuda!"]

    private let systemNames = ["Basso", "Funk", "Sosumi", "Frog", "Hero", "Pop", "Purr", "Submarine", "Bottle", "Blow", "Glass", "Morse", "Ping", "Tink"]

    override init() {
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.attach(customPlayer)
        engine.attach(pitchUnit)
        engine.connect(customPlayer, to: pitchUnit, format: stereoFormat)
        engine.connect(pitchUnit, to: engine.mainMixerNode, format: stereoFormat)
        try? engine.start()
    }

    func play(pack: SoundPack, force: Double, volume: Float, streak: Int) {
        let strength = SlapStrength(force: force)
        switch pack {
        case .whatsapp:
            if let url = Bundle.main.url(forResource: "whatsapp", withExtension: "mp3") {
                _ = playURL(url, force: force)
            }
        case .miau:
            // Na maioria das vezes mia; de vez em quando (~30%) solta o rizz, nunca duas vezes seguidas
            let useRizz = !lastWasRizz && Double.random(in: 0..<1) < 0.3
            lastWasRizz = useRizz
            if let url = Bundle.main.url(forResource: useRizz ? "rizz" : "meow", withExtension: "mp3") {
                _ = playURL(url, force: force)
            }
        case .gemidos: playMoan(force: force, streak: streak)
        case .voz: speak(strength: strength, force: force, volume: volume, streak: streak)
        case .cartoon: playCartoon(strength: strength, force: force, volume: volume)
        case .sistema: playSystem(strength: strength, volume: volume)
        case .personalizado:
            if !playCustom(force: force) {
                playMoan(force: force, streak: streak)
            }
        }
    }

    // MARK: - Voz

    private func pick(_ list: [String]) -> String {
        var phrase = list.randomElement()!
        if list.count > 1 { while phrase == lastPhrase { phrase = list.randomElement()! } }
        lastPhrase = phrase
        return phrase
    }

    private func speak(strength: SlapStrength, force: Double, volume: Float, streak: Int) {
        let phrase: String
        if streak >= 4 {
            phrase = pick(combo)
        } else {
            switch strength {
            case .leve: phrase = pick(leve)
            case .medio: phrase = pick(medio)
            case .forte: phrase = pick(forte)
            }
        }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: phrase)
        u.voice = AVSpeechSynthesisVoice(language: "pt-BR") ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        u.volume = volume
        // Quanto mais forte o tapa, mais aguda e rápida a reação
        let intensity = min(max((force - 1) / 4, 0), 1)
        u.pitchMultiplier = Float(1.0 + 0.6 * intensity)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * Float(1.05 + 0.25 * intensity)
        u.preUtteranceDelay = 0
        synth.speak(u)
    }

    // MARK: - Sons do macOS

    private func playSystem(strength: SlapStrength, volume: Float) {
        let names: [String]
        switch strength {
        case .leve: names = ["Pop", "Tink", "Bottle", "Purr"]
        case .medio: names = ["Funk", "Frog", "Morse", "Blow", "Ping"]
        case .forte: names = ["Basso", "Sosumi", "Hero", "Submarine", "Glass"]
        }
        guard let name = names.randomElement(), let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        playNSSound(s, volume: volume)
    }

    // MARK: - Personalizado

    func customFiles() -> [URL] {
        let exts: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "caf", "aac"]
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.customFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { exts.contains($0.pathExtension.lowercased()) }
    }

    /// Toca um áudio importado com altura e volume proporcionais à força.
    private func playCustom(force: Double) -> Bool {
        guard let url = customFiles().randomElement() else { return false }
        return playURL(url, force: force)
    }

    private func playURL(_ url: URL, force: Double) -> Bool {
        guard let buffer = loadBuffer(url) else { return false }
        if !engine.isRunning { try? engine.start() }
        let k = MoanSynth.intensity(force: force)
        // De -3 semitons (tapinha) a +5 semitons (tapa forte)
        pitchUnit.pitch = Float(-300 + 800 * k)
        customPlayer.volume = Self.proportionalVolume(intensity: k)
        customPlayer.stop()
        customPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
        customPlayer.play()
        return true
    }

    /// Decodifica o arquivo uma vez e converte para o formato fixo da cadeia (estéreo 44,1 kHz).
    private func loadBuffer(_ url: URL) -> AVAudioPCMBuffer? {
        if let cached = bufferCache[url] { return cached }
        guard let file = try? AVAudioFile(forReading: url),
              let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: src)) != nil else { return nil }
        let result: AVAudioPCMBuffer
        if src.format == stereoFormat {
            result = src
        } else {
            guard let conv = AVAudioConverter(from: src.format, to: stereoFormat) else { return nil }
            let ratio = stereoFormat.sampleRate / src.format.sampleRate
            let cap = AVAudioFrameCount(Double(src.frameLength) * ratio) + 1024
            guard let dst = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: cap) else { return nil }
            var fed = false
            var err: NSError?
            conv.convert(to: dst, error: &err) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true
                status.pointee = .haveData
                return src
            }
            guard err == nil, dst.frameLength > 0 else { return nil }
            result = dst
        }
        bufferCache[url] = result
        return result
    }

    func playFile(_ url: URL) {
        guard let s = NSSound(contentsOf: url, byReference: true) else { return }
        playNSSound(s, volume: 1)
    }

    private func playNSSound(_ s: NSSound, volume: Float) {
        s.volume = volume
        s.delegate = self
        activeSounds.append(s)
        s.play()
    }

    // MARK: - Gemidos (sintetizados)

    /// Volume proporcional à força: tapinha = baixinho, tapa forte = alto.
    static func proportionalVolume(intensity k: Double) -> Float {
        Float(0.18 + 0.82 * pow(min(max(k, 0), 1), 0.8))
    }

    private func playMoan(force: Double, streak: Int) {
        if !engine.isRunning { try? engine.start() }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        // Tapas seguidos vão "esquentando": cada um soma intensidade
        let k = min(1, MoanSynth.intensity(force: force) + 0.08 * Double(max(0, streak - 1)))
        let buffer = streak >= 4
            ? MoanSynth.makeSequence(intensity: k, count: 2, format: format)
            : MoanSynth.make(intensity: k, format: format)
        guard let buffer else { return }
        player.volume = Self.proportionalVolume(intensity: k)
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    // MARK: - Desenho animado (sintetizado)

    private func playCartoon(strength: SlapStrength, force: Double, volume: Float) {
        if !engine.isRunning { try? engine.start() }
        let shift = 1.0 + min(max((force - 1) / 6, 0), 0.6)
        let buffer: AVAudioPCMBuffer?
        switch strength {
        case .leve: buffer = [makeSlap(), makeSqueak(shift: shift)].randomElement()!
        case .medio: buffer = [makeBoing(shift: shift), makeSqueak(shift: shift), makeSlap()].randomElement()!
        case .forte: buffer = [makeBonk(), makeBoing(shift: shift * 0.8)].randomElement()!
        }
        guard let buffer else { return }
        player.volume = volume
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func render(duration: Double, _ sample: (Double, Double) -> Double) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(duration * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            data[i] = Float(max(-1, min(1, sample(t, t / duration))))
        }
        return buf
    }

    /// Estalo de tapa: ruído filtrado com decaimento rápido.
    private func makeSlap() -> AVAudioPCMBuffer? {
        var lp = 0.0
        return render(duration: 0.18) { t, _ in
            let noise = Double.random(in: -1...1)
            lp += 0.35 * (noise - lp)
            let env = exp(-t * 38)
            return (lp * 1.6 + noise * 0.25) * env * 0.9
        }
    }

    /// "Boing" de mola.
    private func makeBoing(shift: Double) -> AVAudioPCMBuffer? {
        var phase = 0.0
        return render(duration: 0.75) { t, p in
            let f = (140 + 260 * p) * shift * (1 + 0.12 * sin(2 * .pi * 11 * t))
            phase += 2 * .pi * f / 44100
            let env = exp(-t * 4.5) * min(1, t * 200)
            return (sin(phase) + 0.3 * sin(2 * phase)) * env * 0.6
        }
    }

    /// Guincho de borracha subindo.
    private func makeSqueak(shift: Double) -> AVAudioPCMBuffer? {
        var phase = 0.0
        return render(duration: 0.28) { t, p in
            let f = (650 + 1300 * p * p) * shift + 40 * sin(2 * .pi * 35 * t)
            phase += 2 * .pi * f / 44100
            let env = sin(.pi * p) * 0.5
            return sin(phase) * env
        }
    }

    /// "Bonk" grave de pancada na cabeça.
    private func makeBonk() -> AVAudioPCMBuffer? {
        var phase = 0.0
        return render(duration: 0.45) { t, _ in
            let f = 90 + 220 * exp(-t * 18)
            phase += 2 * .pi * f / 44100
            let body = sin(phase) * exp(-t * 7)
            let click = Double.random(in: -1...1) * exp(-t * 120) * 0.7
            return (body * 0.9 + click)
        }
    }
}

extension SoundPlayer: NSSoundDelegate {
    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        activeSounds.removeAll { $0 === sound }
    }
}
