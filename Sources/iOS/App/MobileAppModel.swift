import SwiftUI
import Observation
import UIKit

@MainActor @Observable
final class MobileAppModel {
    let bluetooth = MobileBluetoothController()
    var project: PixelProject
    var selectedFrameID: UUID
    var color = Color.cyan
    var erasing = false
    var isPlaying = false
    var message = "Pronto. Nenhuma conexão ou transmissão automática."
    var selectedPage: DashboardPage = .time
    var pageInterval = 4.0
    private(set) var isCasting = false
    var twentyFourHour = true
    var alarmTime = Date()
    var alarmEnabled = false
    var alarmWeekdays: UInt8 = 0x7F
    var alarmVolume = 50.0
    private(set) var alarmConfigured = false
    var brightness = 50.0
    var clockStyle = 0
    var mode = 0
    var cityQuery = "Joinville"
    private(set) var locations: [WeatherLocation] = []
    private(set) var location: WeatherLocation?
    private(set) var weather: WeatherSnapshot?
    private(set) var weatherStatus = "Busque uma cidade para consultar o clima."
    private(set) var citySearchStatus = "Busque e selecione uma cidade."
    private(set) var isLoadingWeather = false
    var library: [MobileLibraryEntry] = []
    @ObservationIgnored private let weatherService = WeatherService()
    @ObservationIgnored private var castTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var weatherTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastWeatherAttempt: Date?
    @ObservationIgnored private var searchGeneration = UUID()
    @ObservationIgnored private var weatherGeneration = UUID()

    init() {
        let initial = PixelProject(); project = initial; selectedFrameID = initial.frames[0].id
        let defaults = UserDefaults.standard
        if let saved = defaults.data(forKey: "mobile.location"), let item = try? JSONDecoder().decode(WeatherLocation.self, from: saved) { location = item; cityQuery = item.name }
        if let data = defaults.data(forKey: "mobile.weather"), let saved = try? JSONDecoder().decode(MobileWeatherCache.self, from: data), saved.location.id == location?.id {
            weather = WeatherSnapshot(temperature: saved.temperature, code: saved.code, fetchedAt: saved.fetchedAt, observationTime: saved.observationTime, location: saved.location)
            weatherStatus = "Último clima salvo. Atualize quando houver internet."
            lastWeatherAttempt = saved.fetchedAt
        }
        if let saved = defaults.object(forKey: "mobile.alarmTime") as? Date { alarmTime = saved }
        alarmEnabled = defaults.bool(forKey: "mobile.alarmEnabled")
        alarmConfigured = defaults.bool(forKey: "mobile.alarmConfigured")
        if let days = defaults.object(forKey: "mobile.alarmWeekdays") as? Int { alarmWeekdays = UInt8(clamping: days) & 0x7F }
        if let volume = defaults.object(forKey: "mobile.alarmVolume") as? Double { alarmVolume = min(100, max(0, volume)) }
        refreshLibrary()
    }
    var currentFrame: PixelFrame { project.frames.first { $0.id == selectedFrameID } ?? project.frames[0] }
    var canSend: Bool { bluetooth.canSend && !bluetooth.isBusy && !isCasting }
    var dashboardValues: DashboardValues {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let current = weather.flatMap { Date().timeIntervalSince($0.dataDate) <= 3600 ? $0 : nil }
        return DashboardValues(date: Date(), timeZone: .current, twentyFourHour: twentyFourHour, alarmEnabled: alarmEnabled, alarmHour: parts.hour ?? 0, alarmMinute: parts.minute ?? 0, temperature: current?.temperature, weatherCode: current?.code, alarmConfigured: alarmConfigured)
    }
    func sendPage() { sendImage(DashboardRenderer.render(page: selectedPage, values: dashboardValues), label: "Painel · \(selectedPage.title)") }
    func startCasting() {
        stopCasting()
        guard bluetooth.canSend, !bluetooth.isBusy else { message = "Conecte o aparelho e aguarde o envio atual."; return }
        isCasting = true
        message = "Painel ativo enquanto o app permanece em primeiro plano."
        castTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let delay = self?.castStep(index: &index) else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }
    private func castStep(index: inout Int) -> Double? {
        guard isCasting else { return nil }
        guard bluetooth.canSend else { stopCasting(); message = "Painel interrompido: conexão indisponível."; return nil }
        guard !bluetooth.isBusy else { return 0.2 }
        selectedPage = DashboardPage.allCases[index % DashboardPage.allCases.count]
        sendPage(); index += 1; refreshWeatherIfNeeded()
        return pageInterval
    }
    func stopCasting() { castTask?.cancel(); castTask = nil; isCasting = false }
    func becameInactive() { stopCasting(); stopPlayback(); message = "Transmissão pausada fora do primeiro plano. O Ditoo mantém a última imagem." }
    func enteredBackground() { becameInactive(); bluetooth.stopScan() }
    private func sendImage(_ rgb: [UInt8], label: String) { do { bluetooth.send(try DivoomProtocol.image(rgb: rgb), label: label) } catch { message = error.localizedDescription } }
    func sendFrame() { sendImage(currentFrame.rgb, label: "Imagem 16 × 16") }
    func sendAnimation() { guard canSend else { return }; bluetooth.sendAnimation(frames: project.frames.map(\.rgb), durationMilliseconds: project.durationMilliseconds) }
    func applyClock() { bluetooth.send([DivoomProtocol.timeFormat(twentyFourHour: twentyFourHour), DivoomProtocol.clock(style: UInt8(clockStyle), twentyFourHour: twentyFourHour, color: Self.rgb(color))], label: "Relógio") }
    func applyAlarm() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        do {
            let payload = try DivoomProtocol.alarm(slot: 0, enabled: alarmEnabled, hour: parts.hour ?? 0, minute: parts.minute ?? 0, weekdays: alarmWeekdays, volume: Int(alarmVolume))
            bluetooth.send([payload], label: "Alarme 0")
            alarmConfigured = true
            let d = UserDefaults.standard
            d.set(alarmTime, forKey: "mobile.alarmTime"); d.set(alarmEnabled, forKey: "mobile.alarmEnabled"); d.set(true, forKey: "mobile.alarmConfigured"); d.set(Int(alarmWeekdays), forKey: "mobile.alarmWeekdays"); d.set(alarmVolume, forKey: "mobile.alarmVolume")
            message = "Configuração encaminhada; confirme o alarme no aparelho."
        } catch { message = error.localizedDescription }
    }
    static func rgb(_ color: Color) -> (UInt8, UInt8, UInt8) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt8(clamping: Int(r * 255)), UInt8(clamping: Int(g * 255)), UInt8(clamping: Int(b * 255)))
    }
    func paint(x: Int, y: Int) {
        guard !isPlaying, (0..<16).contains(x), (0..<16).contains(y), let index = project.frames.firstIndex(where: { $0.id == selectedFrameID }) else { return }
        let rgb = erasing ? (UInt8(0), UInt8(0), UInt8(0)) : Self.rgb(color)
        let offset = (y * 16 + x) * 3
        project.frames[index].rgb.replaceSubrange(offset..<(offset + 3), with: [rgb.0, rgb.1, rgb.2])
    }
    func addFrame(duplicate: Bool) { guard project.frames.count < 60 else { message = "Limite de 60 quadros."; return }; var frame = duplicate ? currentFrame : PixelFrame(); frame.id = UUID(); project.frames.append(frame); selectedFrameID = frame.id }
    func deleteFrame() { guard project.frames.count > 1 else { return }; project.frames.removeAll { $0.id == selectedFrameID }; selectedFrameID = project.frames[0].id }
    func clearFrame() { guard let index = project.frames.firstIndex(where: { $0.id == selectedFrameID }) else { return }; project.frames[index].rgb = [UInt8](repeating: 0, count: 768) }
    func togglePlayback() {
        if isPlaying { stopPlayback(); return }; isPlaying = true
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let duration = self?.project.durationMilliseconds else { return }
                do { try await Task.sleep(for: .milliseconds(duration)) } catch { return }
                self?.advanceFrame()
            }
        }
    }
    private func advanceFrame() {
        guard isPlaying else { return }
        let index = project.frames.firstIndex { $0.id == selectedFrameID } ?? 0
        selectedFrameID = project.frames[(index + 1) % project.frames.count].id
    }
    func stopPlayback() { playbackTask?.cancel(); playbackTask = nil; isPlaying = false }
    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            stopPlayback()
            if url.pathExtension.lowercased() == "json" {
                project = try PixelProject.load(from: url)
            } else {
                let media = try PixelMedia.importMedia(from: url)
                project.frames = media.frames; project.name = url.deletingPathExtension().lastPathComponent; project.durationMilliseconds = media.durationMilliseconds
                message = media.hasVariableTiming ? "GIF importado; tempos normalizados para \(media.durationMilliseconds) ms por quadro." : "Mídia importada em 16 × 16."
            }
            selectedFrameID = project.frames[0].id
        } catch { message = error.localizedDescription }
    }
    func exportData(kind: MobileExportKind) throws -> Data {
        if kind == .project { return try JSONEncoder().encode(project) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(kind == .gif ? "gif" : "png")
        defer { try? FileManager.default.removeItem(at: url) }
        var output = project; if kind == .png { output.frames = [currentFrame] }
        try PixelMedia.export(output, to: url, animated: kind == .gif)
        return try Data(contentsOf: url)
    }
    private var libraryURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true) }
    func refreshLibrary() { library = ((try? FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { MobileLibraryEntry(id: $0, name: $0.deletingPathExtension().lastPathComponent) } }
    func saveToLibrary() { do { try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true); let name = project.name.replacingOccurrences(of: "/", with: "-"); let url = libraryURL.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).json"); try JSONEncoder().encode(project).write(to: url, options: .atomic); refreshLibrary(); message = "Projeto guardado neste iPhone." } catch { message = error.localizedDescription } }
    func searchCity() {
        searchTask?.cancel(); let generation = UUID(); searchGeneration = generation
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        locations = []
        guard query.count >= 2 else { citySearchStatus = "Digite pelo menos duas letras da cidade."; return }
        citySearchStatus = "Buscando cidades…"
        let service = weatherService
        searchTask = Task { [weak self] in
            do {
                let result = try await service.fetchLocations(query: query)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.locations = result
                self.citySearchStatus = result.isEmpty ? "Nenhuma cidade encontrada." : "Selecione uma cidade."
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.citySearchStatus = error.localizedDescription
            }
        }
    }
    func chooseCity(_ city: WeatherLocation) {
        searchTask?.cancel(); searchGeneration = UUID(); citySearchStatus = "Cidade selecionada."; weatherTask?.cancel(); weatherGeneration = UUID()
        location = city; cityQuery = city.name; weather = nil; locations = []; isLoadingWeather = false; lastWeatherAttempt = nil
        if let data = try? JSONEncoder().encode(city) { UserDefaults.standard.set(data, forKey: "mobile.location") }
        refreshWeather()
    }
    func refreshWeatherIfNeeded() { guard let location, !isLoadingWeather else { return }; _ = location; if let lastWeatherAttempt, Date().timeIntervalSince(lastWeatherAttempt) < 900 { return }; refreshWeather() }
    func refreshWeather() {
        guard let location, !isLoadingWeather else { return }; isLoadingWeather = true; lastWeatherAttempt = Date(); weatherStatus = "Atualizando clima…"
        let generation = UUID(); weatherGeneration = generation
        weatherTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.weatherGeneration == generation { self.isLoadingWeather = false } }
            do { let result = try await self.weatherService.fetchCurrent(location: location); guard !Task.isCancelled, self.weatherGeneration == generation else { return }; self.weather = result
                let cache = MobileWeatherCache(temperature: result.temperature, code: result.code, fetchedAt: result.fetchedAt, observationTime: result.observationTime, location: result.location)
                if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: "mobile.weather") }
                self.weatherStatus = "Clima atualizado." } catch { guard !Task.isCancelled, self.weatherGeneration == generation else { return }; self.weatherStatus = "Clima indisponível: \(error.localizedDescription)" }
        }
    }
}
struct MobileLibraryEntry: Identifiable { let id: URL; let name: String }

private struct MobileWeatherCache: Codable {
    let temperature: Double
    let code: Int
    let fetchedAt: Date
    let observationTime: Date?
    let location: WeatherLocation
}
