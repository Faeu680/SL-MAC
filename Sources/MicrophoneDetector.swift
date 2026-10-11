import Foundation
import AVFoundation

/// Alternativa para Macs sem acelerômetro: detecta o som seco de um tapa pelo microfone.
final class MicrophoneDetector {
    var onImpact: ((Double) -> Void)?
    var onLevel: ((Double) -> Void)?
    /// Limiar de pico (0...1 de amplitude).
    var threshold: Double = 0.4

    private let engine = AVAudioEngine()
    private var ambient: Double = 0.01
    private var refractoryUntil: TimeInterval = 0
    private(set) var isRunning = false

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { completion(ok) } }
        default: completion(false)
        }
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var peak: Float = 0
        var sum: Float = 0
        for i in 0..<n {
            let v = abs(data[i])
            peak = max(peak, v)
            sum += v * v
        }
        let rms = Double((sum / Float(n)).squareRoot())
        let p = Double(peak)
        onLevel?(p)

        let now = ProcessInfo.processInfo.systemUptime
        // Um tapa é um transiente: pico alto e bem acima do ruído ambiente.
        if p > threshold && p > ambient * 8 && now >= refractoryUntil {
            refractoryUntil = now + 0.2
            onImpact?(p)
        } else {
            ambient = ambient * 0.95 + rms * 0.05
        }
    }
}
