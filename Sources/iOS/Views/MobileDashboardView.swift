import SwiftUI

struct MobileDashboardView: View {
    @Bindable var model: MobileAppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MobilePixelPreview(rgb: DashboardRenderer.render(page: model.selectedPage, values: model.dashboardValues))
                        .frame(maxWidth: 320).frame(maxWidth: .infinity)
                }
                MobileDashboardSummary(model: model)
                Picker("Página", selection: $model.selectedPage) {
                    ForEach(DashboardPage.allCases) { page in Text(page.title).tag(page) }
                }.pickerStyle(.segmented)
                MobileCard(title: "Seu painel no Ditoo") {
                    Text("Data, hora, alarme e clima alternam enquanto este app está aberto em primeiro plano.").foregroundStyle(.secondary)
                    Stepper("Trocar a cada \(Int(model.pageInterval)) segundos", value: $model.pageInterval, in: 2...30, step: 1)
                    Toggle("Formato de 24 horas", isOn: $model.twentyFourHour)
                    if model.isCasting {
                        Button("Pausar painel", systemImage: "pause.fill", action: model.stopCasting).buttonStyle(.borderedProminent)
                    } else {
                        Button("Iniciar painel", systemImage: "play.fill", action: model.startCasting).buttonStyle(.borderedProminent).disabled(!model.canSend)
                        Button("Enviar apenas esta página", action: model.sendPage).disabled(!model.canSend)
                    }
                    Text("Ao sair do app, a transmissão para. O aparelho conserva a última imagem; o painel não executa sozinho no firmware.").font(.caption).foregroundStyle(.secondary)
                }
                MobileWeatherView(model: model)
                Text(model.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding()
        }.navigationTitle("Painel")
            .toolbar { MobileConnectionStatus(controller: model.bluetooth) }
    }
}

struct MobileWeatherView: View {
    @Bindable var model: MobileAppModel
    var body: some View {
        MobileCard(title: "Clima") {
            MobileCitySearchRow(model: model)
            Text(model.citySearchStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(model.locations) { city in
                Button { model.chooseCity(city) } label: {
                    VStack(alignment: .leading) { Text(city.name); Text("\(city.region), \(city.country)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 4)
            }
            if let location = model.location { Text(location.name).font(.headline) }
            if let weather = model.weather {
                Label { Text("\(weather.temperature, format: .number.precision(.fractionLength(1))) °C · \(weather.conditionDescription)") } icon: { Image(systemName: weather.symbolName) }
                Text("Dados de \(weather.dataDate, format: .dateTime.hour().minute())").font(.caption).foregroundStyle(.secondary)
            }
            if model.isLoadingWeather { ProgressView() }
            Text(model.weatherStatus).font(.caption).foregroundStyle(.secondary)
            Button("Atualizar clima", action: model.refreshWeather).disabled(model.location == nil || model.isLoadingWeather)
            Text("Open-Meteo · Consulta pela internet. Sem dados recentes, a tela mostra --.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct MobileCitySearchRow: View {
    @Bindable var model: MobileAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            TextField("Cidade", text: $model.cityQuery).textFieldStyle(.roundedBorder)
                .submitLabel(.search).onSubmit(model.searchCity)
            Button("Buscar", action: model.searchCity)
        }
    }
}

struct MobilePixelPreview: View {
    let rgb: [UInt8]
    var body: some View {
        Canvas { context, size in
            let cell = min(size.width, size.height) / 16
            for y in 0..<16 { for x in 0..<16 {
                let index = (y * 16 + x) * 3
                guard index + 2 < rgb.count else { continue }
                let color = Color(red: Double(rgb[index]) / 255, green: Double(rgb[index + 1]) / 255, blue: Double(rgb[index + 2]) / 255)
                context.fill(Path(CGRect(x: Double(x) * cell, y: Double(y) * cell, width: cell - 0.5, height: cell - 0.5)), with: .color(color))
            } }
        }.aspectRatio(1, contentMode: .fit).background(.black).clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("Prévia de pixels, 16 por 16")
    }
}

struct MobileCard<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08)))
    }
}

struct MobileConnectionStatus: View {
    let controller: MobileBluetoothController
    var body: some View {
        Label(controller.isConnected ? "Conectado" : "Offline", systemImage: controller.isConnected ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption).foregroundStyle(controller.isConnected ? Color.green : Color.secondary)
    }
}


struct MobileDashboardSummary: View {
    let model: MobileAppModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                MobileSummaryRow(title: "Data", value: context.date.formatted(.dateTime.day().month(.wide).year()))
                MobileSummaryRow(title: "Hora", value: Self.clock(context.date, twentyFour: model.twentyFourHour))
                MobileSummaryRow(title: "Horário do alarme", value: model.alarmConfigured ? Self.clock(model.alarmTime, twentyFour: model.twentyFourHour) : "Não configurado")
                if model.alarmConfigured {
                    Text(model.alarmEnabled ? "Alarme ativado no app" : "Alarme desativado no app")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let weather = model.weather, context.date.timeIntervalSince(weather.dataDate) <= 3600 {
                    MobileSummaryRow(title: "Clima", value: "\(weather.temperature.formatted(.number.precision(.fractionLength(0)))) °C · \(weather.conditionDescription)")
                } else {
                    MobileSummaryRow(title: "Clima", value: "Sem dados recentes")
                }
                Text("O horário do alarme é a configuração do iPhone; ainda sem leitura de confirmação do Ditoo.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private static func clock(_ date: Date, twentyFour: Bool) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = c.hour ?? 0
        if twentyFour { return String(format: "%02d:%02d", hour, c.minute ?? 0) }
        return String(format: "%02d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, c.minute ?? 0, hour < 12 ? "AM" : "PM")
    }
}


struct MobileSummaryRow: View {
    let title: LocalizedStringResource
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LabeledContent { Text(value) } label: { Text(title) }
        }
    }
}
