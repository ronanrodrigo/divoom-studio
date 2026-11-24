import Foundation
import Observation

@MainActor
@Observable
final class DashboardModel {
    var cityQuery = "Joinville"
    private(set) var locations: [WeatherLocation] = []
    private(set) var location: WeatherLocation?
    private(set) var weather: WeatherSnapshot?
    private(set) var weatherStatus = "Escolha a cidade para consultar o clima."
    private(set) var isLoadingWeather = false
    private(set) var isSearching = false
    private(set) var searchStatus = "Busque e selecione uma cidade."
    private(set) var isCasting = false
    var selectedPage: DashboardPage = .time
    var pageInterval = 4.0
    private(set) var castingStatus = "O painel ainda não está sendo enviado ao Ditoo."
    @ObservationIgnored private let service = WeatherService()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var weatherTask: Task<Void, Never>?
    @ObservationIgnored private var castTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = UUID()
    @ObservationIgnored private var weatherGeneration = UUID()
    @ObservationIgnored private var lastWeatherAttempt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "dashboard.weatherLocation"),
           let saved = try? JSONDecoder().decode(WeatherLocation.self, from: data) {
            location = saved
            cityQuery = saved.name
        }
        if let data = defaults.data(forKey: "dashboard.weatherSnapshot"),
           let saved = try? JSONDecoder().decode(DashboardWeatherCache.self, from: data),
           saved.location.id == location?.id {
            weather = saved.snapshot
            lastWeatherAttempt = saved.fetchedAt
            weatherStatus = "Último clima salvo. Atualize quando houver internet."
        }
    }

    func search() {
        searchTask?.cancel()
        searchGeneration = UUID()
        isSearching = false
        locations = []
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { searchStatus = "Digite pelo menos duas letras da cidade."; return }
        let generation = UUID()
        searchGeneration = generation
        isSearching = true
        locations = []
        searchStatus = "Buscando cidades…"
        searchTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.searchGeneration == generation { self.isSearching = false } }
            do {
                let result = try await self.service.fetchLocations(query: query)
                guard !Task.isCancelled, self.searchGeneration == generation else { return }
                self.locations = result
                self.searchStatus = result.isEmpty ? "Nenhuma cidade encontrada. Tente incluir o estado." : "Selecione a cidade nos resultados."
            } catch {
                guard !Task.isCancelled, self.searchGeneration == generation else { return }
                self.searchStatus = "Não foi possível buscar a cidade: \(error.localizedDescription)"
            }
        }
    }

    func choose(_ selected: WeatherLocation) {
        searchTask?.cancel()
        searchGeneration = UUID()
        isSearching = false
        searchStatus = "Cidade selecionada."
        weatherTask?.cancel()
        weatherGeneration = UUID()
        isLoadingWeather = false
        lastWeatherAttempt = nil
        location = selected
        weather = nil
        locations = []
        cityQuery = selected.name
        if let data = try? JSONEncoder().encode(selected) { defaults.set(data, forKey: "dashboard.weatherLocation") }
        defaults.removeObject(forKey: "dashboard.weatherSnapshot")
        refreshWeather()
    }

    func refreshWeatherIfNeeded() {
        guard location != nil else { return }
        if let lastWeatherAttempt, Date().timeIntervalSince(lastWeatherAttempt) < 900 { return }
        if let weather, Date().timeIntervalSince(weather.fetchedAt) < 900 { return }
        refreshWeather()
    }

    func refreshWeather() {
        guard let location, !isLoadingWeather else { return }
        weatherTask?.cancel()
        let generation = UUID()
        weatherGeneration = generation
        isLoadingWeather = true
        lastWeatherAttempt = Date()
        weatherStatus = "Atualizando clima…"
        weatherTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.weatherGeneration == generation { self.isLoadingWeather = false } }
            do {
                let result = try await self.service.fetchCurrent(location: location)
                guard !Task.isCancelled, self.weatherGeneration == generation, self.location?.id == location.id else { return }
                self.weather = result
                if let data = try? JSONEncoder().encode(DashboardWeatherCache(snapshot: result)) {
                    self.defaults.set(data, forKey: "dashboard.weatherSnapshot")
                }
                self.weatherStatus = "Clima atualizado."
            } catch {
                guard !Task.isCancelled, self.weatherGeneration == generation else { return }
                self.weatherStatus = "Clima indisponível: \(error.localizedDescription)"
            }
        }
    }

    func values(date: Date, alarmEnabled: Bool, alarmTime: Date, twentyFourHour: Bool, alarmConfigured: Bool) -> DashboardValues {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let currentWeather = weather.flatMap { date.timeIntervalSince($0.dataDate) <= 3600 ? $0 : nil }
        return DashboardValues(date: date, timeZone: .current, twentyFourHour: twentyFourHour,
                               alarmEnabled: alarmEnabled, alarmHour: parts.hour ?? 0, alarmMinute: parts.minute ?? 0,
                               temperature: currentWeather?.temperature, weatherCode: currentWeather?.code, alarmConfigured: alarmConfigured)
    }

    func start(bluetooth: BluetoothController, values: @escaping @MainActor () -> DashboardValues) {
        stop()
        guard bluetooth.isConnected, !bluetooth.isBusy else { castingStatus = "Conecte o Ditoo e aguarde o envio atual."; return }
        isCasting = true
        castingStatus = "Alternando data, hora, alarme e clima no Ditoo."
        let session = bluetooth.sessionIdentifier
        castTask = Task { [weak self, weak bluetooth] in
            var index = 0
            while !Task.isCancelled {
                guard let delay = self?.castStep(bluetooth: bluetooth, session: session, index: &index, values: values) else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    private func castStep(bluetooth: BluetoothController?, session: UUID, index: inout Int,
                          values: @MainActor () -> DashboardValues) -> Double? {
        guard isCasting else { return nil }
        guard let bluetooth, bluetooth.isConnected else {
            isCasting = false
            castingStatus = "Transmissão interrompida: Ditoo desconectado."
            return nil
        }
        guard bluetooth.sessionIdentifier == session else {
            isCasting = false
            castingStatus = "A conexão mudou. Inicie a transmissão novamente quando quiser."
            return nil
        }
        guard !bluetooth.isBusy else { return 0.2 }
        let page = DashboardPage.allCases[index % DashboardPage.allCases.count]
        selectedPage = page
        do {
            bluetooth.send(try DivoomProtocol.image(rgb: DashboardRenderer.render(page: page, values: values())), label: "Painel · \(page.title)")
        } catch {
            isCasting = false
            castingStatus = "Falha ao montar o painel: \(error.localizedDescription)"
            return nil
        }
        index += 1
        refreshWeatherIfNeeded()
        return pageInterval
    }

    func stop() {
        castTask?.cancel()
        castTask = nil
        isCasting = false
        castingStatus = "Transmissão pausada; o Ditoo mantém a última imagem enviada."
    }
}

/// Stored separately from the selected city so a stale/mismatched cache never changes selection.
private struct DashboardWeatherCache: Codable {
    let temperature: Double
    let code: Int
    let fetchedAt: Date
    let observationTime: Date?
    let location: WeatherLocation

    init(snapshot: WeatherSnapshot) {
        temperature = snapshot.temperature
        code = snapshot.code
        fetchedAt = snapshot.fetchedAt
        observationTime = snapshot.observationTime
        location = snapshot.location
    }

    var snapshot: WeatherSnapshot {
        WeatherSnapshot(temperature: temperature, code: code, fetchedAt: fetchedAt,
                        observationTime: observationTime, location: location)
    }
}
