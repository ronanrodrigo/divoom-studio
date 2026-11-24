#if os(macOS)
import Foundation
import XCTest
@testable import DivoomStudio

final class DashboardCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_478_400)
    private let city = WeatherLocation(id: 100, name: "Cidade de teste", region: "SC", country: "Brasil",
                                       latitude: -26.3, longitude: -48.8, timezone: "America/Sao_Paulo")

    @MainActor
    func testRestoresFreshSnapshotAndSelectedCityWithoutStartingWork() throws {
        try withDefaults { defaults in
            try saveLocation(city, to: defaults)
            let observation = now.addingTimeInterval(-600)
            try saveCache(location: city, fetchedAt: now.addingTimeInterval(-300), observationTime: observation, to: defaults)
            let model = DashboardModel(defaults: defaults)
            XCTAssertEqual(model.location, city)
            XCTAssertEqual(model.cityQuery, city.name)
            XCTAssertEqual(model.weather?.temperature, 23.5)
            XCTAssertEqual(model.weather?.code, 61)
            XCTAssertEqual(model.weather?.fetchedAt, now.addingTimeInterval(-300))
            XCTAssertEqual(model.weather?.observationTime, observation)
            XCTAssertEqual(values(model).temperature, 23.5)
            XCTAssertEqual(values(model).weatherCode, 61)
            XCTAssertFalse(model.isLoadingWeather)
            XCTAssertFalse(model.isSearching)
            XCTAssertFalse(model.isCasting)
        }
    }

    @MainActor
    func testRejectsSnapshotForAnotherCityWithoutChangingSelectedLocation() throws {
        try withDefaults { defaults in
            try saveLocation(city, to: defaults)
            let other = WeatherLocation(id: 200, name: "Outra cidade", region: "PR", country: "Brasil",
                                        latitude: -25.4, longitude: -49.2, timezone: "America/Sao_Paulo")
            try saveCache(location: other, fetchedAt: now, observationTime: now, to: defaults)
            let model = DashboardModel(defaults: defaults)
            XCTAssertEqual(model.location, city)
            XCTAssertEqual(model.cityQuery, city.name)
            XCTAssertNil(model.weather)
            XCTAssertNil(values(model).temperature)
            XCTAssertNil(values(model).weatherCode)
        }
    }

    @MainActor
    func testRecentFetchDoesNotMakeAnOldObservationFreshForTheRenderer() throws {
        try withDefaults { defaults in
            try saveLocation(city, to: defaults)
            try saveCache(location: city, fetchedAt: now, observationTime: now.addingTimeInterval(-3601), to: defaults)
            let model = DashboardModel(defaults: defaults)
            XCTAssertNotNil(model.weather, "Retain the last observation for the UI, even while offline")
            XCTAssertNil(values(model).temperature, "The renderer must not label an old observation as current")
            XCTAssertNil(values(model).weatherCode)
        }
    }

    @MainActor
    func testCacheWithoutObservationTimeUsesFetchTimeForFreshness() throws {
        try withDefaults { defaults in
            try saveLocation(city, to: defaults)
            try saveCache(location: city, fetchedAt: now.addingTimeInterval(-300), observationTime: nil, to: defaults)
            let model = DashboardModel(defaults: defaults)
            XCTAssertEqual(values(model).temperature, 23.5)
            let later = model.values(date: now.addingTimeInterval(3601), alarmEnabled: false, alarmTime: now,
                                     twentyFourHour: true, alarmConfigured: false)
            XCTAssertNil(later.temperature)
            XCTAssertNil(later.weatherCode)
        }
    }

    @MainActor
    func testNoSavedCityAndCorruptCachesCannotRestoreUnselectedWeather() throws {
        try withDefaults { defaults in
            try saveCache(location: city, fetchedAt: now, observationTime: now, to: defaults)
            let noCity = DashboardModel(defaults: defaults)
            XCTAssertNil(noCity.location)
            XCTAssertNil(noCity.weather)
            try saveLocation(city, to: defaults)
            defaults.set(Data("invalid JSON".utf8), forKey: "dashboard.weatherSnapshot")
            let corrupt = DashboardModel(defaults: defaults)
            XCTAssertEqual(corrupt.location, city)
            XCTAssertNil(corrupt.weather)
            XCTAssertFalse(corrupt.isLoadingWeather)
        }
    }

    @MainActor
    private func values(_ model: DashboardModel) -> DashboardValues {
        model.values(date: now, alarmEnabled: false, alarmTime: now, twentyFourHour: true, alarmConfigured: false)
    }

    private func saveLocation(_ location: WeatherLocation, to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(location), forKey: "dashboard.weatherLocation")
    }

    private func saveCache(location: WeatherLocation, fetchedAt: Date, observationTime: Date?, to defaults: UserDefaults) throws {
        struct StoredSnapshot: Encodable {
            let temperature: Double
            let code: Int
            let fetchedAt: Date
            let observationTime: Date?
            let location: WeatherLocation
        }
        let stored = StoredSnapshot(temperature: 23.5, code: 61, fetchedAt: fetchedAt,
                                    observationTime: observationTime, location: location)
        defaults.set(try JSONEncoder().encode(stored), forKey: "dashboard.weatherSnapshot")
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "DivoomStudio.DashboardCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
#endif
