import XCTest
@testable import DivoomStudio

final class WeatherServiceTests: XCTestCase {
    private var joinville: WeatherLocation {
        WeatherLocation(id: 3459712, name: "Joinville", region: "Santa Catarina", country: "Brasil", latitude: -26.30444, longitude: -48.84556, timezone: "America/Sao_Paulo")
    }
    func testGeocodingDecodesOptionalFieldsAndRoundTripsSavedCity() throws {
        let json = #"{"results":[{"id":3459712,"name":"Joinville","latitude":-26.30444,"longitude":-48.84556,"admin1":"Santa Catarina","country":"Brasil","timezone":"America/Sao_Paulo"},{"id":1,"name":"Small town","latitude":0,"longitude":0}]}"#
        let result = try WeatherService.decodeLocations(Data(json.utf8))
        XCTAssertEqual(result[0], joinville)
        XCTAssertEqual(result[1].region, "")
        XCTAssertEqual(result[1].timezone, "UTC")
        XCTAssertEqual(try JSONDecoder().decode(WeatherLocation.self, from: JSONEncoder().encode(joinville)), joinville)
        XCTAssertTrue(try WeatherService.decodeLocations(Data("{}".utf8)).isEmpty)
    }
    func testCurrentConditionsUseResponseTimeZoneAndSeparateFetchTime() throws {
        let json = #"{"timezone":"America/Sao_Paulo","current":{"time":"2026-11-23T10:00","temperature_2m":26.0,"weather_code":3}}"#
        let fetched = Date(timeIntervalSince1970: 0)
        let snapshot = try WeatherService.decodeCurrent(Data(json.utf8), location: joinville, fetchedAt: fetched)
        XCTAssertEqual(snapshot.temperature, 26)
        XCTAssertEqual(snapshot.code, 3)
        XCTAssertEqual(snapshot.conditionDescription, "Nublado")
        XCTAssertEqual(snapshot.symbolName, "cloud.fill")
        XCTAssertEqual(snapshot.fetchedAt, fetched)
        let expected = ISO8601DateFormatter().date(from: "2026-11-23T13:00:00Z")!
        XCTAssertEqual(snapshot.observationTime, expected)
        XCTAssertEqual(snapshot.dataDate, expected)
    }
    func testMalformedCurrentDataIsRejectedAndUnknownCodeHasFallback() throws {
        XCTAssertThrowsError(try WeatherService.decodeCurrent(Data("{}".utf8), location: joinville))
        XCTAssertThrowsError(try WeatherService.decodeCurrent(Data(#"{"current":{"time":"2026-11-23T10:00","temperature_2m":null,"weather_code":0}}"#.utf8), location: joinville))
        let unknown = WeatherSnapshot(temperature: -4, code: 999, fetchedAt: Date(), observationTime: nil, location: joinville)
        XCTAssertEqual(unknown.conditionDescription, "Condição indisponível")
        XCTAssertEqual(unknown.symbolName, "questionmark.circle")
    }
}
