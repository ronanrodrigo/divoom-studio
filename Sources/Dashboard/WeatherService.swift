import Foundation

/// Open-Meteo public geocoding and current-conditions API.
/// https://open-meteo.com/en/docs/geocoding-api
/// https://open-meteo.com/en/docs (WMO weather interpretation codes)
struct WeatherLocation: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezone: String

    enum CodingKeys: String, CodingKey { case id, name, region = "admin1", country, latitude, longitude, timezone }

    init(id: Int, name: String, region: String, country: String, latitude: Double, longitude: Double, timezone: String) {
        self.id = id; self.name = name; self.region = region; self.country = country
        self.latitude = latitude; self.longitude = longitude; self.timezone = timezone
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        region = try values.decodeIfPresent(String.self, forKey: .region) ?? ""
        country = try values.decodeIfPresent(String.self, forKey: .country) ?? ""
        timezone = try values.decodeIfPresent(String.self, forKey: .timezone) ?? "UTC"
    }
}

struct WeatherSnapshot: Equatable, Sendable {
    let temperature: Double
    let code: Int
    let fetchedAt: Date
    let observationTime: Date?
    let location: WeatherLocation

    var conditionDescription: String {
        switch code {
        case 0: "Céu limpo"
        case 1: "Predomínio de sol"
        case 2: "Parcialmente nublado"
        case 3: "Nublado"
        case 45, 48: "Nevoeiro"
        case 51, 53, 55: "Garoa"
        case 56, 57: "Garoa congelante"
        case 61, 63, 65: "Chuva"
        case 66, 67: "Chuva congelante"
        case 71, 73, 75, 77: "Neve"
        case 80, 81, 82: "Pancadas de chuva"
        case 85, 86: "Pancadas de neve"
        case 95: "Trovoadas"
        case 96, 99: "Trovoadas com granizo"
        default: "Condição indisponível"
        }
    }
    var symbolName: String {
        switch code {
        case 0, 1: "sun.max.fill"
        case 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "questionmark.circle"
        }
    }
    var dataDate: Date { observationTime ?? fetchedAt }
}

struct WeatherService: Sendable {
    enum ServiceError: LocalizedError {
        case invalidResponse, httpStatus(Int), tooLarge, invalidLocation
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "O serviço retornou dados de clima inválidos."
            case .httpStatus(let status): "O serviço de clima respondeu HTTP \(status)."
            case .tooLarge: "A resposta de clima excedeu o limite permitido."
            case .invalidLocation: "As coordenadas da cidade são inválidas."
            }
        }
    }

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchLocations(query: String) async throws -> [WeatherLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let url = Self.url(host: "geocoding-api.open-meteo.com", path: "/v1/search", items: [
            .init(name: "name", value: trimmed), .init(name: "count", value: "5"),
            .init(name: "language", value: "pt"), .init(name: "format", value: "json")
        ])
        return try Self.decodeLocations(await load(url))
    }
    func fetchCurrent(location: WeatherLocation) async throws -> WeatherSnapshot {
        guard location.latitude.isFinite, location.longitude.isFinite,
              (-90...90).contains(location.latitude), (-180...180).contains(location.longitude) else { throw ServiceError.invalidLocation }
        let url = Self.url(host: "api.open-meteo.com", path: "/v1/forecast", items: [
            .init(name: "latitude", value: String(location.latitude)), .init(name: "longitude", value: String(location.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"), .init(name: "temperature_unit", value: "celsius"),
            .init(name: "timezone", value: "auto")
        ])
        return try Self.decodeCurrent(await load(url), location: location)
    }
    private func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ServiceError.httpStatus(http.statusCode) }
        guard data.count <= 2_000_000 else { throw ServiceError.tooLarge }
        return data
    }
    private static func url(host: String, path: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = path; components.queryItems = items
        return components.url!
    }
    static func decodeLocations(_ data: Data) throws -> [WeatherLocation] {
        struct Response: Decodable { let results: [WeatherLocation]? }
        return try JSONDecoder().decode(Response.self, from: data).results ?? []
    }
    static func decodeCurrent(_ data: Data, location: WeatherLocation, fetchedAt: Date = Date()) throws -> WeatherSnapshot {
        struct Response: Decodable {
            struct Current: Decodable {
                let time: String
                let temperature_2m: Double
                let weather_code: Int
            }
            let timezone: String?
            let current: Current
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.current.temperature_2m.isFinite else { throw ServiceError.invalidResponse }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: response.timezone ?? location.timezone) ?? TimeZone(secondsFromGMT: 0)
        return WeatherSnapshot(temperature: response.current.temperature_2m, code: response.current.weather_code,
                               fetchedAt: fetchedAt, observationTime: formatter.date(from: response.current.time), location: location)
    }
}
