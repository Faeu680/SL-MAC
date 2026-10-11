import SwiftUI

struct MenuView: View {
    @EnvironmentObject var engine: SlapEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stats
            meter
            Divider()
            settings
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { engine.panelVisible = true }
        .onDisappear { engine.panelVisible = false }
    }

    private var header: some View {
        HStack {
            Text(engine.justSlapped ? "😵" : "🖐️").font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text("SlapMac").font(.headline)
                Text(engine.sensorStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $engine.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Pausar / ativar")
            Button {
                engine.quit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Fechar o SlapMac (⌘Q)")
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            statBox(title: "Tapas", value: "\(engine.totalSlaps)")
            statBox(title: "Último", value: engine.lastForce > 0 ? String(format: "%.1fx", engine.lastForce) : "—")
            statBox(title: "Recorde", value: engine.strongest > 0 ? String(format: "%.1fx", engine.strongest) : "—")
        }
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Impacto ao vivo").font(.caption)
                Spacer()
                Text(engine.activeSensor == .microfone
                     ? String(format: "%.2f / %.2f", engine.liveLevel, engine.currentThreshold)
                     : String(format: "%.3f g / %.3f g", engine.liveLevel, engine.currentThreshold))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let full = engine.currentThreshold * 2
                let frac = min(engine.liveLevel / max(full, 0.0001), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(engine.liveLevel >= engine.currentThreshold ? Color.red : Color.accentColor)
                        .frame(width: max(4, geo.size.width * frac))
                        .animation(.linear(duration: 0.06), value: frac)
                    Rectangle().fill(Color.red.opacity(0.8))
                        .frame(width: 2)
                        .offset(x: geo.size.width * 0.5 - 1)
                }
            }
            .frame(height: 8)
            Text("A linha vermelha é o limiar. Ajuste a sensibilidade para que digitar não passe dela.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Sensibilidade")
                    Spacer()
                    Text("\(Int(engine.sensitivity * 100))%").foregroundStyle(.secondary).monospacedDigit()
                }.font(.callout)
                Slider(value: $engine.sensitivity, in: 0...1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Intervalo entre tapas")
                    Spacer()
                    Text(String(format: "%.1f s", engine.cooldown)).foregroundStyle(.secondary).monospacedDigit()
                }.font(.callout)
                Slider(value: $engine.cooldown, in: 0.2...3, step: 0.1)
            }
            Picker("Sons", selection: $engine.pack) {
                ForEach(SoundPack.allCases) { Text($0.title).tag($0) }
            }
            customSounds
            Picker("Sensor", selection: $engine.mode) {
                ForEach(DetectionMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Volume proporcional à força", isOn: $engine.scaleVolume)
            Toggle("Abrir ao iniciar sessão", isOn: Binding(
                get: { engine.launchAtLogin },
                set: { engine.setLaunchAtLogin($0) }
            ))
        }
    }

    private var customSounds: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    engine.importAudio()
                } label: {
                    Label("Importar áudio…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                if !engine.customSounds.isEmpty {
                    Button("Abrir pasta") { engine.openCustomFolder() }.controlSize(.small)
                }
            }
            if engine.customSounds.isEmpty {
                if engine.pack == .personalizado {
                    Text("Nenhum áudio importado ainda. Importe um mp3, m4a ou wav.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(engine.customSounds, id: \.self) { url in
                            HStack(spacing: 6) {
                                Button { engine.preview(url) } label: { Image(systemName: "play.circle") }
                                    .buttonStyle(.plain).help("Ouvir")
                                Text(url.lastPathComponent)
                                    .font(.caption).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { engine.removeCustomSound(url) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remover")
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 110)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                if engine.pack != .personalizado {
                    Text("Escolha \"Personalizado\" em Sons para usar seus áudios.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Testar tapa") { engine.testSlap() }
            Button("Zerar") { engine.resetStats() }
            Spacer()
            Button(role: .destructive) {
                engine.quit()
            } label: {
                Label("Fechar SlapMac", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .tint(.red)
        }
    }
}
