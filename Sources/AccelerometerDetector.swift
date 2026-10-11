import Foundation
import IOKit
import IOKit.hid

/// Lê o acelerômetro escondido dos MacBooks Apple Silicon (AppleSPUHIDDevice,
/// usage page 0xFF00 / usage 3) e detecta impactos (tapas).
final class AccelerometerDetector {
    /// Chamado (em thread de background) quando um tapa é detectado. Valor = pico em g.
    var onImpact: ((Double) -> Void)?
    /// Chamado (em background, ~15x/s) com o nível dinâmico atual em g.
    var onLevel: ((Double) -> Void)?

    /// Limiar em g. Lido pela thread do sensor.
    var threshold: Double = 0.25

    private var thread: Thread?
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    // Estado do filtro (somente na thread do sensor)
    private var baseline: (Double, Double, Double)? = nil
    private var inEvent = false
    private var eventPeak = 0.0
    private var eventEnd: TimeInterval = 0
    private var refractoryUntil: TimeInterval = 0
    private var levelPeak = 0.0
    private var lastLevelPost: TimeInterval = 0
    private var chosenDevice: IOHIDDevice?

    private(set) var isRunning = false

    static func isAvailable() -> Bool {
        let matching = IOServiceMatching("AppleSPUHIDDevice")
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(it) }
        var found = false
        var s = IOIteratorNext(it)
        while s != 0 {
            if let page = IORegistryEntryCreateCFProperty(s, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
               let usage = IORegistryEntryCreateCFProperty(s, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
               page == 0xFF00, usage == 3 {
                found = true
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return found
    }

    /// Liga os drivers do SPU para que comecem a enviar relatórios.
    private func wakeSensors() {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var s = IOIteratorNext(it)
        while s != 0 {
            IORegistryEntrySetCFProperty(s, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(s, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(s, "ReportInterval" as CFString, 1000 as CFNumber)
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        guard Self.isAvailable() else { return false }
        wakeSensors()

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDPrimaryUsagePageKey: 0xFF00,
            kIOHIDPrimaryUsageKey: 3,
        ] as CFDictionary)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, !devices.isEmpty else {
            return false
        }
        manager = mgr
        baseline = nil
        chosenDevice = nil

        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            for dev in devices {
                IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDDeviceRegisterInputReportCallback(dev, self.reportBuffer, 64, { context, _, sender, _, _, report, length in
                    guard let context else { return }
                    let me = Unmanaged<AccelerometerDetector>.fromOpaque(context).takeUnretainedValue()
                    me.handle(report: report, length: length, sender: sender)
                }, ctx)
                IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
            ready.signal()
            // Mantém a thread viva
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 1.0, false)
            }
            for dev in devices {
                IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
        t.name = "SlapMac.Accelerometer"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        ready.wait()
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        thread?.cancel()
        if let rl = runLoop { CFRunLoopStop(rl) }
        thread = nil
        runLoop = nil
        if let mgr = manager { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
        isRunning = false
    }

    private func handle(report: UnsafeMutablePointer<UInt8>, length: CFIndex, sender: UnsafeMutableRawPointer?) {
        guard length >= 18 else { return }
        // Existem dois dispositivos com o mesmo uso; usamos apenas o primeiro que reportar.
        if let sender {
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            if chosenDevice == nil { chosenDevice = dev }
            if chosenDevice !== dev { return }
        }
        let raw = UnsafeRawPointer(report)
        let x = Double(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 6, as: Int32.self))) / 65536.0
        let y = Double(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 10, as: Int32.self))) / 65536.0
        let z = Double(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 14, as: Int32.self))) / 65536.0
        process(x: x, y: y, z: z)
    }

    private func process(x: Double, y: Double, z: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard var b = baseline else { baseline = (x, y, z); return }

        let dx = x - b.0, dy = y - b.1, dz = z - b.2
        let dyn = (dx * dx + dy * dy + dz * dz).squareRoot()

        // Linha de base lenta (filtro passa-alta); quase não se move durante impactos.
        let alpha = dyn > threshold ? 0.002 : 0.02
        b.0 += alpha * dx; b.1 += alpha * dy; b.2 += alpha * dz
        baseline = b

        levelPeak = max(levelPeak, dyn)
        if now - lastLevelPost > 0.066 {
            let lvl = levelPeak
            levelPeak = 0
            lastLevelPost = now
            onLevel?(lvl)
        }

        if inEvent {
            eventPeak = max(eventPeak, dyn)
            if now >= eventEnd {
                inEvent = false
                refractoryUntil = now + 0.15
                onImpact?(eventPeak)
            }
        } else if dyn > threshold && now >= refractoryUntil {
            inEvent = true
            eventPeak = dyn
            eventEnd = now + 0.04 // janela de 40 ms para medir o pico
        }
    }
}
