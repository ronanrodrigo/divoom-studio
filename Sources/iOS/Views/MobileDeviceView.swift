import SwiftUI

struct MobileDeviceView: View {
    @Bindable var model: MobileAppModel
    var body: some View {
        List {
            Section("Bluetooth") {
                Text("O iPhone procura o canal Bluetooth Low Energy do Ditoo, geralmente identificado como Light. O canal de áudio é separado.").font(.callout)
                Text(model.bluetooth.status).foregroundStyle(.secondary)
                Picker("Protocolo", selection: Binding(get: { model.bluetooth.profileSelection }, set: { model.bluetooth.profileSelection = $0 })) {
                    ForEach(BLEProtocolSelection.allCases) { profile in Text(profile.rawValue).tag(profile) }
                }
                Text(model.bluetooth.compatibilityStatus).font(.caption).foregroundStyle(.secondary)
                Text(model.bluetooth.profileDescription).font(.caption2).foregroundStyle(.secondary)
                ForEach(model.bluetooth.devices) { device in
                    Button {
                        model.bluetooth.selectedDeviceID = device.id
                    } label: {
                        HStack { VStack(alignment: .leading) { Text(device.name); Text("Sinal: \(device.rssi) dBm").font(.caption).foregroundStyle(.secondary) }; Spacer(); if model.bluetooth.selectedDeviceID == device.id { Image(systemName: "checkmark") } }
                    }
                }
                HStack {
                    Button("Buscar", action: model.bluetooth.scan)
                    Button("Parar busca", action: model.bluetooth.stopScan)
                }
                if model.bluetooth.isConnected { Button("Desconectar") { model.stopCasting(); model.bluetooth.disconnect() } }
                else { Button("Conectar", action: model.bluetooth.connect).disabled(model.bluetooth.selectedDeviceID == nil || model.bluetooth.isBusy) }
                Text("A conexão real exige um iPhone físico e um Ditoo com canal BLE compatível. O simulador permite editar e explorar a interface, mas não comprova Bluetooth.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Controles") {
                NavigationLink("Relógio, brilho e modos") { MobileControlsView(model: model) }
                NavigationLink("Alarme") { MobileAlarmView(model: model) }
            }
            Section("Seus arquivos") {
                NavigationLink("Biblioteca local") { MobileLibraryView(model: model) }
                NavigationLink("Diagnóstico Bluetooth") { MobileLogsView(controller: model.bluetooth) }
            }
            Section { Text(model.message).font(.callout).foregroundStyle(.secondary) }
        }.navigationTitle("Aparelho")
    }
}

struct MobileControlsView: View {
    @Bindable var model: MobileAppModel
    var body: some View {
        Form {
            Section("Relógio") {
                Toggle("Formato de 24 horas", isOn: $model.twentyFourHour)
                Picker("Estilo", selection: $model.clockStyle) { ForEach(0..<6) { Text("Estilo \($0 + 1)").tag($0) } }
                ColorPicker("Cor", selection: $model.color, supportsOpacity: false)
                Button("Aplicar relógio", action: model.applyClock).disabled(!model.canSend)
                Button("Sincronizar horário") { model.bluetooth.send([DivoomProtocol.syncTime(Date())], label: "Horário") }.disabled(!model.canSend)
            }
            Section("Tela") {
                Slider(value: $model.brightness, in: 0...100, step: 1) { Text("Brilho") }
                Text("Brilho: \(Int(model.brightness))%")
                Button("Aplicar brilho") { model.bluetooth.send([DivoomProtocol.brightness(Int(model.brightness))], label: "Brilho") }.disabled(!model.canSend)
                Button("Apagar tela") { model.bluetooth.send([DivoomProtocol.screen(false)], label: "Apagar tela") }.disabled(!model.canSend)
                Button("Voltar ao relógio") { model.bluetooth.send([DivoomProtocol.channel(0)], label: "Relógio") }.disabled(!model.canSend)
            }
            Section("Modo da tela") {
                Picker("Modo", selection: $model.mode) {
                    Text("Relógio").tag(0); Text("Iluminação").tag(1); Text("Nuvem").tag(2); Text("Efeitos VJ").tag(3); Text("Visualizador").tag(4); Text("Personalizado").tag(5)
                }
                Button("Aplicar modo") { model.bluetooth.send([DivoomProtocol.channel(UInt8(model.mode))], label: "Modo") }.disabled(!model.canSend)
            }
            Section { Text("Recursos variam conforme o firmware. Confira cada alteração na tela do aparelho; transmissão não comprova resultado visual.").font(.caption) }
        }.navigationTitle("Relógio e modos")
    }
}

struct MobileAlarmView: View {
    @Bindable var model: MobileAppModel
    let weekdays = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
    var body: some View {
        Form {
            Section("Primeiro alarme · slot 0") {
                Toggle("Ativado", isOn: $model.alarmEnabled)
                DatePicker("Horário", selection: $model.alarmTime, displayedComponents: .hourAndMinute)
                Slider(value: $model.alarmVolume, in: 0...100, step: 1) { Text("Volume") }
                Text("Volume: \(Int(model.alarmVolume))%")
            }
            Section("Repetir") {
                ForEach(0..<7) { index in
                    Toggle(weekdays[index], isOn: Binding(get: { model.alarmWeekdays & (1 << index) != 0 }, set: { enabled in if enabled { model.alarmWeekdays |= 1 << index } else { model.alarmWeekdays &= ~(1 << index) } }))
                }
            }
            Section {
                Button("Enviar alarme ao Ditoo", action: model.applyAlarm).disabled(!model.canSend)
                Text("A configuração fica salva no iPhone após o envio. Confirme o agendamento e o disparo no Ditoo. Não é um despertador local do iOS.").font(.caption)
                Text(model.message).font(.callout).foregroundStyle(.secondary)
            }
        }.navigationTitle("Alarme")
    }
}

struct MobileLibraryView: View {
    let model: MobileAppModel
    var body: some View {
        List {
            Section { Button("Guardar projeto atual", action: model.saveToLibrary) }
            Section("Projetos neste iPhone") {
                if model.library.isEmpty { Text("Nenhum projeto salvo. Crie pixels no editor.").foregroundStyle(.secondary) }
                ForEach(model.library) { entry in Button(entry.name) { model.importFile(entry.id) } }
            }
            Section { Text(model.message).font(.caption) }
        }.navigationTitle("Biblioteca")
    }
}

struct MobileLogsView: View {
    let controller: MobileBluetoothController
    var body: some View {
        List {
            Section { ShareLink("Compartilhar registro", item: controller.exportLog()); Text(controller.status).font(.caption) }
            ForEach(controller.logs) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.date, format: .dateTime.hour().minute().second()) · \(entry.direction)").font(.caption).foregroundStyle(.secondary)
                    Text(entry.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }.navigationTitle("Diagnóstico")
    }
}
