import SwiftUI

struct DashboardView: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardSummary(model: model)
                HStack(alignment: .top, spacing: 22) {
                    DashboardDevicePanel(model: model)
                    DashboardWeatherSettings(dashboard: model.dashboard)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
         .task {
            while !Task.isCancelled {
                model.dashboard.refreshWeatherIfNeeded()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onDisappear { model.dashboard.stop() }
    }
}

struct DashboardSummary: View {
    let model: AppModel
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LazyVGrid(columns: columns, spacing: 18) {
                DashboardInfoCard(title: "Data", symbol: "calendar", color: .orange) {
                    Text(context.date, format: .dateTime.day().month(.wide))
                        .font(.system(size: 29, weight: .semibold))
                    Text(context.date, format: .dateTime.weekday(.wide).year()).foregroundStyle(.secondary)
                }
                DashboardInfoCard(title: "Hora", symbol: "clock", color: .cyan) {
                    Text(DashboardFormatting.time(context.date, twentyFourHour: model.twentyFourHour))
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                }
                DashboardInfoCard(title: "Horário do alarme", symbol: "alarm", color: .pink) {
                    Text(model.hasConfiguredAlarm ? DashboardFormatting.time(model.alarmTime, twentyFourHour: model.twentyFourHour) : "Não configurado")
                        .font(.system(size: 29, weight: .semibold, design: .monospaced))
                    Text(model.alarmEnabled ? "Ativado no app" : "Desativado no app").foregroundStyle(.secondary)
                    Text("Configuração do app · ajuste em Alarmes")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Ainda sem leitura de confirmação do aparelho.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                DashboardWeatherCard(dashboard: model.dashboard, now: context.date)
            }
        }
    }
}

struct DashboardWeatherCard: View {
    let dashboard: DashboardModel
    let now: Date
    var body: some View {
        DashboardInfoCard(title: "Clima", symbol: dashboard.weather?.symbolName ?? "cloud", color: .blue) {
            if let weather = dashboard.weather {
                HStack(alignment: .firstTextBaseline) {
                    Text(weather.temperature, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 36, weight: .semibold))
                    Text("°C").font(.title2)
                    Text(weather.conditionDescription).foregroundStyle(.secondary)
                }
                Text(dashboard.location?.name ?? "").font(.subheadline)
                HStack {
                    Text("Consultado às \(weather.fetchedAt, format: .dateTime.hour().minute())")
                    if now.timeIntervalSince(weather.dataDate) > 3600 { Text("· Desatualizado").foregroundStyle(.orange) }
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text(dashboard.isLoadingWeather ? "Atualizando…" : "— °C")
                    .font(.system(size: 36, weight: .semibold))
                Text(dashboard.weatherStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DashboardInfoCard<Content: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    let color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label { Text(title).font(.subheadline.weight(.medium)) } icon: { Image(systemName: symbol).foregroundStyle(color) }
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.16)))
    }
}

struct DashboardDevicePanel: View {
    let model: AppModel
    @Bindable var dashboard: DashboardModel
    init(model: AppModel) {
        self.model = model
        self.dashboard = model.dashboard
    }
    var body: some View {
        StudioCard(title: "Painel no Ditoo", symbol: "hifispeaker") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let values = model.dashboard.values(date: context.date, alarmEnabled: model.alarmEnabled,
                                                     alarmTime: model.alarmTime, twentyFourHour: model.twentyFourHour, alarmConfigured: model.hasConfiguredAlarm)
                FrameThumbnail(rgb: DashboardRenderer.render(page: model.dashboard.selectedPage, values: values))
                    .frame(width: 192, height: 192)
                    .accessibilityLabel("Prévia pixelada: \(model.dashboard.selectedPage.title)")
                    .frame(maxWidth: .infinity)
            }
            Picker("Prévia", selection: $dashboard.selectedPage) {
                ForEach(DashboardPage.allCases) { page in Text(page.title).tag(page) }
            }.disabled(model.dashboard.isCasting)
            Stepper("Cada tela: \(Int(model.dashboard.pageInterval)) segundos", value: $dashboard.pageInterval, in: 3...15, step: 1)
            HStack {
                if model.dashboard.isCasting {
                    Button("Parar painel", systemImage: "stop.fill", action: model.dashboard.stop)
                } else {
                    Button("Exibir no Ditoo", systemImage: "play.fill") {
                        model.dashboard.start(bluetooth: model.bluetooth) { [weak model] in
                            guard let model else {
                                return DashboardValues(date: Date(), timeZone: .current, twentyFourHour: true,
                                                       alarmEnabled: false, alarmHour: 0, alarmMinute: 0, temperature: nil, weatherCode: nil, alarmConfigured: false)
                            }
                            return model.dashboard.values(date: Date(), alarmEnabled: model.alarmEnabled,
                                                          alarmTime: model.alarmTime, twentyFourHour: model.twentyFourHour, alarmConfigured: model.hasConfiguredAlarm)
                        }
                    }.buttonStyle(.borderedProminent).disabled(!model.canSend)
                }
                if !model.bluetooth.isConnected {
                    Button("Conectar", action: model.bluetooth.connect).disabled(model.bluetooth.isBusy)
                }
            }
            Text(model.dashboard.castingStatus).font(.caption).foregroundStyle(.secondary)
            Text("As quatro informações alternam na tela de 16 × 16 pixels. Mantenha este painel aberto no Mac para atualizar a hora e o clima.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(minWidth: 310, maxWidth: .infinity)
    }
}

struct DashboardWeatherSettings: View {
    @Bindable var dashboard: DashboardModel
    var body: some View {
        StudioCard(title: "Cidade do clima", symbol: "location") {
            HStack {
                TextField("Cidade", text: $dashboard.cityQuery).textFieldStyle(.roundedBorder)
                    .onSubmit(dashboard.search)
                Button("Buscar", action: dashboard.search).disabled(dashboard.isSearching)
            }
            if dashboard.isSearching { ProgressView().controlSize(.small) }
            Text(dashboard.searchStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(dashboard.locations) { location in
                Button { dashboard.choose(location) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(location.name).font(.subheadline.weight(.medium))
                        Text([location.region, location.country].filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
            }
            if let location = dashboard.location {
                Label(location.name, systemImage: "mappin.circle.fill")
                Text([location.region, location.country].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Button("Atualizar clima", action: dashboard.refreshWeather).disabled(dashboard.isLoadingWeather)
            }
            Text(dashboard.weatherStatus).font(.caption).foregroundStyle(.secondary)
            Text("Atualização a cada 15 minutos enquanto o painel é transmitido. Sem dados recentes, o Ditoo mostra traços.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Dados meteorológicos: Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                .font(.caption)
        }.frame(minWidth: 300, maxWidth: .infinity)
    }
}

enum DashboardFormatting {
    static func time(_ date: Date, twentyFourHour: Bool) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        if twentyFourHour { return String(format: "%02d:%02d", hour, parts.minute ?? 0) }
        return String(format: "%02d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, parts.minute ?? 0, hour < 12 ? "AM" : "PM")
    }
}
