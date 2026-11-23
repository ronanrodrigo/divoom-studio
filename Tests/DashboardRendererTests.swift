import Foundation
import XCTest
@testable import DivoomStudio

final class DashboardRendererTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let newYear = Date(timeIntervalSince1970: 1_767_225_600)

    func testAllPagesAreDistinctRowMajorRGBFrames() {
        let frames = DashboardPage.allCases.map { render($0) }
        XCTAssertEqual(Set(frames).count, DashboardPage.allCases.count)
        for frame in frames {
            XCTAssertEqual(frame.count, 768)
            XCTAssertTrue(frame.contains(where: { $0 != 0 }))
            for row in [0, 8, 9, 15] {
                XCTAssertEqual(mask(frame, row: row), "................")
            }
        }
        XCTAssertEqual(pixel(frames[0], x: 5, y: 1), [255, 204, 57])
    }

    func testDateFollowsTimeZoneAcrossMonthAndYearBoundaries() {
        let january = render(.date)
        let december = render(.date, timeZone: TimeZone(secondsFromGMT: -3 * 3_600))
        // January 1 (01–01) becomes December 31 (31–12) at the same instant.
        XCTAssertEqual(mask(january, row: 10), "###..#...###..#.")
        XCTAssertEqual(mask(december, row: 10), "###..#....#..###")
        XCTAssertEqual(mask(january, row: 12), "#.#..#.###.#..#.")
    }

    func testClockFollowsTimeZoneAndChangesWithMinute() {
        let midnight = render(.time)
        let minuteLater = render(.time, date: newYear.addingTimeInterval(60))
        let followingHour = render(.time, timeZone: TimeZone(secondsFromGMT: 3_600))
        XCTAssertEqual(mask(midnight, row: 10), "###.###..###.###")
        XCTAssertEqual(mask(midnight, row: 11), "#.#.#.##.#.#.#.#")
        XCTAssertEqual(mask(minuteLater, row: 10), "###.###..###..#.")
        XCTAssertEqual(mask(followingHour, row: 10), "###..#...###.###")
        XCTAssertEqual(render(.time, date: newYear.addingTimeInterval(59)), midnight)
    }

    func testTwelveHourClockShowsTwelveAndDistinguishesAMFromPM() {
        let midnight = render(.time, twentyFourHour: false)
        let midday = render(.time, date: newYear.addingTimeInterval(43_200), twentyFourHour: false)
        XCTAssertEqual(mask(midnight, row: 10), ".#..###..###.###")
        XCTAssertEqual(mask(midnight, row: 10), mask(midday, row: 10))
        XCTAssertNotEqual(mask(midnight, row: 2), mask(midday, row: 2))
    }

    func testDisabledAlarmKeepsConfiguredTimeWithDistinctIconAndColor() {
        let enabled = render(.alarm)
        let disabled = render(.alarm, alarmEnabled: false)
        XCTAssertEqual(mask(enabled, row: 10), "###.###..###.###")
        XCTAssertEqual(mask(enabled, row: 10), mask(disabled, row: 10))
        XCTAssertNotEqual(mask(enabled, row: 2), mask(disabled, row: 2))
        XCTAssertEqual(pixel(enabled, x: 0, y: 10), [255, 103, 164])
        XCTAssertEqual(pixel(disabled, x: 0, y: 10), [137, 145, 163])
        XCTAssertNotEqual(enabled, render(.alarm, alarmMinute: 31))
        XCTAssertEqual(render(.alarm, alarmHour: -1, alarmMinute: 80), render(.alarm, alarmHour: 0, alarmMinute: 59))
    }

    func testUnconfiguredAlarmShowsPlaceholderWithoutTimeOrPeriod() {
        let unset = render(.alarm, alarmConfigured: false)
        XCTAssertEqual(mask(unset, row: 11), ".......#........")
        XCTAssertEqual(mask(unset, row: 12), ".##.##....##.##.")
        XCTAssertEqual(mask(unset, row: 13), ".......#........")
        XCTAssertEqual(pixel(unset, x: 1, y: 12), [137, 145, 163])
        XCTAssertEqual(
            unset,
            render(.alarm, twentyFourHour: false, alarmEnabled: false, alarmHour: 23, alarmMinute: 58, alarmConfigured: false)
        )
        XCTAssertNotEqual(unset, render(.alarm, alarmEnabled: false))
    }

    func testUnavailableWeatherHasPlaceholderAndNonFiniteInputsAreSafe() {
        let missing = render(.weather, temperature: nil, weatherCode: nil)
        XCTAssertEqual(mask(missing, row: 10), "................")
        XCTAssertEqual(mask(missing, row: 12), ".....##.##......")
        XCTAssertEqual(missing, render(.weather, temperature: .nan, weatherCode: nil))
        XCTAssertEqual(missing, render(.weather, temperature: .infinity, weatherCode: nil))
        XCTAssertEqual(missing, render(.weather, temperature: nil, weatherCode: 999))
    }

    func testWeatherIconAndTemperatureUpdateIndependently() {
        let sun = render(.weather, temperature: -3.6, weatherCode: 0)
        let rain = render(.weather, temperature: -4, weatherCode: 63)
        XCTAssertNotEqual(mask(sun, row: 1), mask(rain, row: 1))
        XCTAssertEqual(mask(sun, row: 12), mask(rain, row: 12))
        XCTAssertEqual(mask(sun, row: 12), "...##.###.......")
        XCTAssertEqual(sun, render(.weather, temperature: -4, weatherCode: 0))
        XCTAssertNotEqual(sun, render(.weather, temperature: 4, weatherCode: 0))
        XCTAssertEqual(render(.weather, temperature: 1000), render(.weather, temperature: 99))
        XCTAssertEqual(render(.weather, temperature: -1000), render(.weather, temperature: -99))
    }

    private func render(
        _ page: DashboardPage,
        date: Date? = nil,
        timeZone: TimeZone? = nil,
        twentyFourHour: Bool = true,
        alarmEnabled: Bool = true,
        alarmHour: Int = 6,
        alarmMinute: Int = 30,
        temperature: Double? = 24,
        weatherCode: Int? = 0,
        alarmConfigured: Bool = true
    ) -> [UInt8] {
        DashboardRenderer.render(
            page: page,
            values: DashboardValues(
                date: date ?? newYear,
                timeZone: timeZone ?? utc,
                twentyFourHour: twentyFourHour,
                alarmEnabled: alarmEnabled,
                alarmHour: alarmHour,
                alarmMinute: alarmMinute,
                temperature: temperature,
                weatherCode: weatherCode,
                alarmConfigured: alarmConfigured
            )
        )
    }

    private func mask(_ frame: [UInt8], row: Int) -> String {
        (0..<16).map { x in
            pixel(frame, x: x, y: row).allSatisfy { $0 == 0 } ? "." : "#"
        }.joined()
    }

    private func pixel(_ frame: [UInt8], x: Int, y: Int) -> ArraySlice<UInt8> {
        let index = (y * 16 + x) * 3
        return frame[index..<(index + 3)]
    }
}
