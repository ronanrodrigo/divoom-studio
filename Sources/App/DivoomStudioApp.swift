import SwiftUI

@main
struct DivoomStudioApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("Divoom Studio", id: "main") {
            StudioView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .tint(.cyan)
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir projeto…", action: { model.openProject() }).keyboardShortcut("o")
                Button("Salvar projeto…", action: model.saveProject).keyboardShortcut("s")
                Button("Importar imagem ou GIF…", action: model.importMedia).keyboardShortcut("i")
            }
        }
    }
}

enum StudioSection: String, CaseIterable, Identifiable {
    case dashboard, device, clock, alarms, editor, library, diagnostics
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .dashboard: "Painel"
        case .device: "Dispositivo"
        case .clock: "Relógio e modos"
        case .alarms: "Alarmes"
        case .editor: "Editor de pixels"
        case .library: "Biblioteca"
        case .diagnostics: "Diagnóstico"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .device: "hifispeaker"
        case .clock: "clock"
        case .alarms: "alarm"
        case .editor: "square.grid.3x3"
        case .library: "square.stack"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

struct StudioView: View {
    let model: AppModel
    @State private var selection: StudioSection? = .dashboard
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Divoom Studio").font(.title2.bold())
                    Text("Seu Ditoo, no Mac").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.top, 26)
                List(StudioSection.allCases, selection: $selection) { item in
                    Label { Text(item.title) } icon: { Image(systemName: item.symbol) }.tag(item)
                }.listStyle(.sidebar)
                ConnectionBadge(controller: model.bluetooth).padding(16)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                StudioHeader(section: selection ?? .clock, controller: model.bluetooth)
                Divider()
                Group {
                    switch selection ?? .clock {
                    case .dashboard: DashboardView(model: model)
                    case .device: DeviceView(controller: model.bluetooth)
                    case .clock: ClockModesView(model: model)
                    case .alarms: AlarmsView(model: model)
                    case .editor: PixelEditorView(model: model)
                    case .library: LibraryView(model: model)
                    case .diagnostics: DiagnosticsView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack { Image(systemName: "info.circle"); Text(model.message).lineLimit(2); Spacer(); Text("Ditoo-Plus · 16 × 16").foregroundStyle(.secondary) }
                    .font(.caption).padding(.horizontal, 20).padding(.vertical, 10)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct ConnectionBadge: View {
    let controller: BluetoothController
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(controller.isConnected ? Color.green : Color.secondary).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.isConnected ? "Bluetooth conectado" : "Desconectado").font(.subheadline.weight(.medium))
                Text(controller.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudioHeader: View {
    let section: StudioSection
    let controller: BluetoothController
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(section.title).font(.largeTitle.bold())
                Text("Crie, ajuste e acompanhe cada envio.").foregroundStyle(.secondary)
            }
            Spacer()
            if controller.isBusy { ProgressView().controlSize(.small) }
            Label(controller.isConnected ? "Conectado" : "Offline", systemImage: controller.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                .font(.subheadline).foregroundStyle(controller.isConnected ? Color.green : Color.secondary)
        }.padding(24)
    }
}

struct DeviceView: View {
    @Bindable var controller: BluetoothController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StudioCard(title: "Conexão Bluetooth", symbol: "antenna.radiowaves.left.and.right") {
                    Text("Selecione o Ditoo emparelhado com este Mac. O áudio pode ser desconectado para abrir o canal de controle.")
                        .foregroundStyle(.secondary)
                    Picker("Dispositivo", selection: $controller.selectedAddress) {
                        Text("Selecione um aparelho").tag("")
                        ForEach(controller.devices) { device in Text("\(device.name) · \(device.address)").tag(device.address) }
                    }
                    HStack {
                        Button("Atualizar lista", action: controller.refreshDevices)
                        Spacer()
                        if controller.isConnected { Button("Desconectar", action: controller.disconnect) }
                        else { Button("Conectar", action: controller.connect).buttonStyle(.borderedProminent).disabled(controller.selectedAddress.isEmpty || controller.isBusy) }
                    }
                }
                StudioCard(title: "Estado do aparelho", symbol: "hifispeaker") {
                    LabeledContent("Transporte", value: "Bluetooth Classic · RFCOMM")
                    LabeledContent("Tela", value: "16 × 16 pixels RGB")
                    LabeledContent("Conexão", value: controller.status)
                    Text("A conexão confirma o canal Bluetooth. Confira no aparelho o resultado dos comandos enviados.").font(.callout).foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: 850)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClockModesView: View {
    @Bindable var model: AppModel
    @State private var lightColor = Color.cyan
    @State private var lightEffect = 0
    @State private var visualEffect = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VerificationNote()
                StudioCard(title: "Relógio", symbol: "clock") {
                    HStack(alignment: .top, spacing: 28) {
                        ClockPreview(color: model.clockColor, twentyFourHour: model.twentyFourHour)
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Estilo", selection: $model.clockStyle) { ForEach(0..<6) { Text("Estilo \($0 + 1)").tag($0) } }
                            Toggle("Formato de 24 horas", isOn: $model.twentyFourHour)
                            ColorPicker("Cor do relógio", selection: $model.clockColor, supportsOpacity: false)
                            HStack {
                                Button("Sincronizar horário do Mac", action: model.syncTime)
                                Button("Aplicar relógio", action: model.applyClock).buttonStyle(.borderedProminent)
                            }.disabled(!model.canSend)
                        }
                    }
                    Text("A prévia ilustra a cor e o horário. A aparência de cada estilo depende do firmware.").font(.caption).foregroundStyle(.secondary)
                }
                StudioCard(title: "Tela e brilho", symbol: "sun.max") {
                    Text("Desligue a iluminação ou retorne ao modo relógio.").foregroundStyle(.secondary)
                    HStack { Slider(value: $model.brightness, in: 0...100, step: 1); Text("\(Int(model.brightness))%").monospacedDigit().frame(width: 45) }
                    HStack {
                        Button("Apagar tela", action: { model.bluetooth.send([DivoomProtocol.screen(false)], label: "Apagar tela") })
                        Button("Voltar ao relógio", action: { model.bluetooth.send([DivoomProtocol.channel(0)], label: "Voltar ao relógio") })
                        Button("Aplicar brilho", action: model.applyBrightness)
                    }.disabled(!model.canSend)
                }
                StudioCard(title: "Modo da tela", symbol: "rectangle.on.rectangle") {
                    Picker("Canal", selection: $model.mode) {
                        Text("Relógio").tag(0)
                        Text("Iluminação").tag(1)
                        Text("Nuvem").tag(2)
                        Text("Efeitos VJ").tag(3)
                        Text("Visualizador de música").tag(4)
                        Text("Personalizado").tag(5)
                    }
                    Text("Disponibilidade e conteúdo dos canais variam conforme o modelo e o firmware.").font(.caption).foregroundStyle(.secondary)
                    Button("Aplicar modo", action: model.applyMode).buttonStyle(.borderedProminent).disabled(!model.canSend)
                    if model.mode == 1 {
                        Divider()
                        ColorPicker("Cor da iluminação", selection: $lightColor, supportsOpacity: false)
                        Picker("Efeito de luz", selection: $lightEffect) {
                            Text("Cor fixa").tag(0)
                            Text("Respiração").tag(1)
                            Text("Efeito 3").tag(2)
                            Text("Efeito 4").tag(3)
                            Text("Efeito 5").tag(4)
                        }
                        Button("Aplicar iluminação") {
                            model.bluetooth.send([DivoomProtocol.light(color: AppModel.rgb(lightColor), brightness: Int(model.brightness), effect: UInt8(lightEffect))], label: "Iluminação")
                        }.disabled(!model.canSend)
                    }
                    if model.mode == 3 || model.mode == 4 {
                        Divider()
                        Picker("Variação", selection: $visualEffect) {
                            ForEach(0..<6) { Text("Variação \($0 + 1)").tag($0) }
                        }
                        Button("Aplicar variação") {
                            let payload = model.mode == 3 ? DivoomProtocol.effect(UInt8(visualEffect)) : DivoomProtocol.visualizer(UInt8(visualEffect))
                            model.bluetooth.send([payload], label: "Variação do modo")
                        }.disabled(!model.canSend)
                    }
                }
            }.padding(24).frame(maxWidth: 900)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClockPreview: View {
    let color: Color
    let twentyFourHour: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 12) {
                Image(systemName: "clock").font(.title2)
                Text(clockText(context.date))
                    .font(.system(size: 35, weight: .semibold, design: .monospaced))
                Text("Prévia ilustrativa").font(.caption2).foregroundStyle(.gray)
            }.foregroundStyle(color).frame(width: 220, height: 180).background(.black, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func clockText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        if twentyFourHour { return String(format: "%02d:%02d", hour, minute) }
        return String(format: "%02d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "AM" : "PM")
    }
}

struct AlarmsView: View {
    @Bindable var model: AppModel
    @State private var weekdays: UInt8 = 0x7F
    @State private var volume = 50.0
    let days = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VerificationNote()
                StudioCard(title: "Alarme do aparelho", symbol: "alarm") {
                    Text("Configuração do primeiro alarme (slot 0).").font(.callout).foregroundStyle(.secondary)
                    Toggle("Alarme ativado", isOn: $model.alarmEnabled)
                    DatePicker("Horário", selection: $model.alarmTime, displayedComponents: .hourAndMinute)
                    Text("Repetir nos dias").font(.subheadline.weight(.medium))
                    HStack {
                        ForEach(0..<7) { index in
                            Toggle(days[index], isOn: Binding(get: { weekdays & (1 << index) != 0 }, set: { value in
                                if value { weekdays |= (1 << index) } else { weekdays &= ~(1 << index) }
                            })).toggleStyle(.button)
                        }
                    }
                    HStack { Text("Volume"); Slider(value: $volume, in: 0...100, step: 1); Text("\(Int(volume))%").monospacedDigit() }
                    Text("Sem dias selecionados: alarme sem repetição semanal. O som usado é o padrão do aparelho.").font(.caption).foregroundStyle(.secondary)
                    Button("Enviar configuração do alarme") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: model.alarmTime)
                        do {
                            let payload = try DivoomProtocol.alarm(slot: 0, enabled: model.alarmEnabled, hour: components.hour ?? 0, minute: components.minute ?? 0, weekdays: weekdays, volume: Int(volume))
                            model.hasConfiguredAlarm = true
                            UserDefaults.standard.set(model.alarmTime, forKey: "alarm.configuredTime")
                            model.bluetooth.send([payload], label: "Alarme 0")
                            model.message = "Configuração enviada ao transporte; confirme o alarme no aparelho."
                        } catch { model.message = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(!model.canSend)
                }
                StudioCard(title: "Validação", symbol: "checklist") {
                    Text("O protocolo do alarme foi identificado em implementações de referência. O agendamento e o disparo ainda precisam ser conferidos neste Ditoo-Plus.")
                        .foregroundStyle(.secondary)
                    Text("O Mac não mantém um despertador local e não precisa ficar aberto depois de um alarme ser aceito pelo aparelho.").font(.callout)
                }
            }.padding(24).frame(maxWidth: 850)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LibraryView: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Projetos guardados neste Mac").font(.headline)
                Spacer()
                Button("Abrir arquivo…", action: { model.openProject() })
                Button("Guardar projeto atual", action: model.addToLibrary).buttonStyle(.borderedProminent)
            }
            if model.library.isEmpty {
                ContentUnavailableView("Sua biblioteca está vazia", systemImage: "square.stack", description: Text("Crie pixels no editor e guarde seu projeto aqui."))
            } else {
                List(model.library) { entry in
                    HStack {
                        Image(systemName: "square.grid.3x3").foregroundStyle(.cyan)
                        Text(entry.name)
                        Spacer()
                        Button("Abrir", action: { model.openProject(url: entry.id) })
                    }.padding(.vertical, 6)
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("Biblioteca local. A comunidade online do Divoom ainda não está integrada.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}

struct DiagnosticsView: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Registro Bluetooth").font(.headline); Spacer(); Button("Exportar registro…", action: model.exportLogs) }
            Text(model.bluetooth.status).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.bluetooth.logs) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                            Text(entry.direction).foregroundStyle(.cyan).frame(width: 45, alignment: .leading)
                            Text(entry.message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(.caption, design: .monospaced))
                    }
                }.padding(16)
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            Text("Transmissão concluída não equivale a confirmação visual. Em caso de travamento, desconecte e reinicie o Ditoo antes de outro envio.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}

struct VerificationNote: View {
    var body: some View {
        Label {
            Text("Controles em validação no Ditoo-Plus. Envie uma alteração por vez e confira o resultado no aparelho.")
        } icon: { Image(systemName: "info.circle") }
        .font(.callout).foregroundStyle(.secondary).padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StudioCard<Content: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label { Text(title).font(.headline) } icon: { Image(systemName: symbol).foregroundStyle(.cyan) }
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06)))
    }
}
