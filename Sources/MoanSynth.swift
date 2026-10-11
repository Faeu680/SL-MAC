import Foundation
import AVFoundation

/// Gemidos femininos sintetizados como sílabas curtas e ofegantes ("ah! ah! aaahh…"):
/// pulso glotal de Rosenberg com jitter/shimmer por ciclo, aspiração no ritmo da glote,
/// filtros de formantes, inspirações (suspiros) entre as sílabas e voz rouca (vocal fry)
/// no final. Sem vibrato contínuo — é o vibrato longo que soa "fantasma".
///
/// `intensity` (0…1) controla número de sílabas, altura, ataque, sopro e duração.
enum MoanSynth {
    struct Vowel { let f: [Double]; let bw: [Double]; let a: [Double] }

    static let ah = Vowel(f: [920, 1520, 2900, 4050], bw: [110, 130, 190, 280], a: [1.0, 0.70, 0.30, 0.14])
    static let eh = Vowel(f: [680, 1900, 2850, 4000], bw: [90, 140, 190, 280], a: [1.0, 0.55, 0.30, 0.12])
    static let ee = Vowel(f: [360, 2600, 3250, 4150], bw: [70, 150, 210, 300], a: [1.0, 0.30, 0.25, 0.10])
    static let mm = Vowel(f: [270, 1250, 2500, 3500], bw: [55, 250, 300, 350], a: [1.0, 0.05, 0.03, 0.02])
    static let breathy = Vowel(f: [800, 1450, 2800, 4200], bw: [350, 400, 450, 550], a: [0.5, 0.8, 0.9, 0.7])

    struct Syllable {
        var from: Vowel, to: Vowel
        var dur: Double
        var f0Peak: Double
        var fall: Double      // fração do tom que cai até o fim (0,3 = cai 30%)
        var amp: Double
        var breath: Double    // 0 = voz limpa, 1 = só sopro
        var attack: Double
        var fry: Bool         // termina com voz rouca/rangida
    }
    enum Segment { case syllable(Syllable), gasp(Double, Double), pause(Double) }

    /// Força do tapa (múltiplos do limiar, >= 1) → intensidade 0…1 em escala logarítmica.
    static func intensity(force: Double) -> Double {
        min(max(log(max(force, 1)) / log(6.0), 0), 1)
    }

    private static func r(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }

    /// Monta a "frase" do gemido de acordo com a intensidade.
    static func script(intensity k: Double) -> [Segment] {
        let peak = (250 + 250 * k) * r(0.95, 1.06)  // tom: 250 Hz (tapinha) … 500 Hz (tapa forte)
        var s: [Segment] = []
        if k < 0.25 {
            // "mmh…" ou "ahh…" baixinho e cheio de sopro
            if Bool.random() {
                s.append(.syllable(Syllable(from: mm, to: mm, dur: r(0.38, 0.55), f0Peak: peak * 0.9, fall: 0.25,
                                            amp: 0.7, breath: 0.55, attack: 0.05, fry: false)))
                s.append(.pause(0.03))
                s.append(.syllable(Syllable(from: ah, to: ah, dur: r(0.3, 0.45), f0Peak: peak, fall: 0.35,
                                            amp: 0.6, breath: 0.75, attack: 0.04, fry: false)))
            } else {
                s.append(.syllable(Syllable(from: ah, to: eh, dur: r(0.45, 0.65), f0Peak: peak, fall: 0.35,
                                            amp: 0.7, breath: 0.7, attack: 0.04, fry: Bool.random())))
            }
        } else if k < 0.6 {
            // (inspira) "ah!… aahh"
            if Bool.random() { s.append(.gasp(r(0.12, 0.2), 0.45)) ; s.append(.pause(0.03)) }
            s.append(.syllable(Syllable(from: ah, to: ah, dur: r(0.2, 0.28), f0Peak: peak, fall: 0.25,
                                        amp: 0.85, breath: 0.45, attack: 0.018, fry: false)))
            s.append(.pause(r(0.06, 0.12)))
            s.append(.syllable(Syllable(from: ah, to: [ah, eh, ee].randomElement()!, dur: r(0.5, 0.75),
                                        f0Peak: peak * r(1.03, 1.1), fall: 0.42, amp: 1.0, breath: 0.4,
                                        attack: 0.02, fry: true)))
        } else {
            // (inspira) "ah! ah! AAAHHH…" subindo a cada sílaba
            s.append(.gasp(r(0.14, 0.24), 0.55))
            s.append(.pause(0.025))
            let shorts = k > 0.85 ? 3 : 2
            for i in 0..<shorts {
                let up = 1 + 0.06 * Double(i)
                s.append(.syllable(Syllable(from: ah, to: Bool.random() ? ah : eh, dur: r(0.16, 0.24),
                                            f0Peak: peak * up, fall: 0.22, amp: 0.8 + 0.07 * Double(i),
                                            breath: 0.35, attack: 0.012, fry: false)))
                s.append(.pause(r(0.04, 0.09)))
                if i == shorts - 1 && Bool.random() { s.append(.gasp(0.1, 0.35)) }
            }
            s.append(.syllable(Syllable(from: ah, to: [ah, ee, eh].randomElement()!, dur: r(0.75, 1.05),
                                        f0Peak: peak * r(1.12, 1.2), fall: 0.5, amp: 1.0, breath: 0.3,
                                        attack: 0.015, fry: true)))
        }
        return s
    }

    static func make(intensity: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(script(intensity: min(max(intensity, 0), 1)), format: format)
    }

    /// Tapas seguidos: dois gemidos emendados, o segundo mais intenso.
    static func makeSequence(intensity: Double, count: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let first = script(intensity: max(0.1, intensity - 0.3))
        let second = script(intensity: min(1, intensity + 0.1))
        return render(first + [.pause(0.08)] + second, format: format)
    }

    // MARK: - Renderização

    private static func glottal(_ ph: Double, _ tp: Double, _ tn: Double) -> Double {
        if ph < tp { return 0.5 * (1 - cos(Double.pi * ph / tp)) }
        if ph < tp + tn { return cos(Double.pi / 2 * (ph - tp) / tn) }
        return 0
    }

    private final class Formants {
        var b0 = [Double](repeating: 0, count: 4), a1 = [Double](repeating: 0, count: 4), a2 = [Double](repeating: 0, count: 4)
        var x1 = [Double](repeating: 0, count: 4), x2 = [Double](repeating: 0, count: 4)
        var y1 = [Double](repeating: 0, count: 4), y2 = [Double](repeating: 0, count: 4)
        var amp = [Double](repeating: 0, count: 4)
        let sr: Double
        init(sr: Double) { self.sr = sr }

        func set(_ from: Vowel, _ to: Vowel, _ w: Double) {
            for j in 0..<4 {
                let f: Double = min(from.f[j] + (to.f[j] - from.f[j]) * w, sr * 0.45)
                let bw: Double = from.bw[j] + (to.bw[j] - from.bw[j]) * w
                let wc: Double = 2 * Double.pi * f / sr
                let alpha: Double = sin(wc) * bw / (2 * f)
                let n: Double = 1 + alpha
                b0[j] = alpha / n
                a1[j] = -2 * cos(wc) / n
                a2[j] = (1 - alpha) / n
                amp[j] = from.a[j] + (to.a[j] - from.a[j]) * w
            }
        }

        func process(_ x: Double) -> Double {
            var y = 0.0
            for j in 0..<4 {
                let yj: Double = b0[j] * (x - x2[j]) - a1[j] * y1[j] - a2[j] * y2[j]
                x2[j] = x1[j]; x1[j] = x
                y2[j] = y1[j]; y1[j] = yj
                y += yj * amp[j]
            }
            return y
        }
    }

    private static func render(_ segments: [Segment], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        var samples: [Double] = []
        samples.reserveCapacity(Int(4 * sr))
        let fil = Formants(sr: sr)

        for seg in segments {
            switch seg {
            case .pause(let d):
                // Pausa com um fio de respiração
                fil.set(breathy, breathy, 0)
                for _ in 0..<Int(d * sr) { samples.append(fil.process(Double.random(in: -1...1)) * 0.02) }

            case .gasp(let d, let amp):
                // Inspiração rápida: sopro filtrado, sobe e corta seco
                fil.set(breathy, ah, 0)
                let n = Int(d * sr)
                var hp = 0.0
                for i in 0..<n {
                    let p = Double(i) / Double(n)
                    if i % 64 == 0 { fil.set(breathy, eh, p) }
                    let env: Double = pow(p, 1.3) * (p > 0.88 ? (1 - p) / 0.12 : 1)
                    let y = fil.process(Double.random(in: -1...1))
                    hp += 0.2 * (y - hp)
                    samples.append((y - hp) * env * amp * 1.6)
                }

            case .syllable(let s):
                let n = Int(s.dur * sr)
                var phase = 0.0, gPrev = 0.0
                var periodJitter = 1.0, periodShimmer = 1.0
                var drift = 0.0
                for i in 0..<n {
                    let p = Double(i) / Double(n)
                    let t = Double(i) / sr
                    if i % 32 == 0 { fil.set(s.from, s.to, p * p * (3 - 2 * p)) }

                    // Tom: sobe rápido até o pico ("ah!") e vai caindo
                    let riseEnd = 0.1
                    var f0: Double
                    if p < riseEnd {
                        let q = p / riseEnd
                        f0 = s.f0Peak * (0.82 + 0.18 * q * q * (3 - 2 * q))
                    } else {
                        let q = (p - riseEnd) / (1 - riseEnd)
                        f0 = s.f0Peak * (1 - s.fall * pow(q, 1.2))
                    }
                    // Voz rouca no final: tom despenca e os ciclos ficam irregulares
                    var fryAmt = 0.0
                    if s.fry && p > 0.72 {
                        fryAmt = min(1, (p - 0.72) / 0.18)
                        f0 = f0 * (1 - fryAmt) + 85 * fryAmt
                    }
                    drift += Double.random(in: -1...1) * 0.002 - drift * 0.01
                    f0 *= (1 + drift) * periodJitter

                    phase += f0 / sr
                    if phase >= 1 {
                        phase -= 1
                        // Nova variação a cada ciclo glotal (é isso que soa humano)
                        let jit = 0.012 + 0.12 * fryAmt
                        periodJitter = 1 + Double.random(in: -jit...jit)
                        periodShimmer = 1 + Double.random(in: -(0.06 + 0.4 * fryAmt)...(0.06 + 0.3 * fryAmt))
                    }
                    let tp = 0.42 + 0.18 * s.breath
                    let tn = 0.12 + 0.12 * s.breath
                    let g = glottal(phase, tp, tn)
                    let dg = (g - gPrev) * sr / max(f0, 60) / 9
                    gPrev = g

                    let voicedEnv: Double = p > 0.82 ? max(0, 1 - (p - 0.82) / 0.16) : 1
                    let voiced = dg * (1 - 0.55 * s.breath) * periodShimmer * voicedEnv
                    let noise = Double.random(in: -1...1)
                    let aspiration = noise * (0.25 + g) * (0.15 + 0.5 * s.breath)
                    let exhale = noise * (p > 0.7 ? min(1, (p - 0.7) / 0.2) * 0.35 : 0)

                    let attack: Double = min(1, t / s.attack)
                    let body: Double = 1 - 0.3 * p
                    let release: Double = p > 0.86 ? pow(max(0, 1 - (p - 0.86) / 0.14), 1.5) : 1
                    let y = fil.process(voiced + aspiration + exhale)
                    samples.append(y * attack * body * release * s.amp)
                }
            }
        }

        // Suaviza agudos, normaliza e grava no buffer
        guard !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        var lp = 0.0, peak = 0.0001
        for i in 0..<samples.count {
            lp += 0.6 * (samples[i] - lp)
            samples[i] = lp
            peak = max(peak, abs(lp))
        }
        let fadeOut = min(samples.count, Int(0.01 * sr))
        for i in 0..<samples.count {
            var v = samples[i] / peak * 0.9
            if i >= samples.count - fadeOut { v *= Double(samples.count - i) / Double(fadeOut) }
            out[i] = Float(v)
        }
        return buf
    }
}
