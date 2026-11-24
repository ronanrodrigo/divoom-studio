#if os(macOS)
import XCTest
@testable import DivoomStudio

final class MacAlarmPreferencesTests: XCTestCase {
    func testLegacyAlarmMigratesWithoutLosingTimeOrEnabledState() throws {
        try withDefaults { defaults in
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            defaults.set(date, forKey: "alarm.configuredTime")
            defaults.set(true, forKey: "alarm.configuredEnabled")
            let alarm = MacAlarmPreferences.load(from: defaults)
            XCTAssertEqual(alarm.time, date)
            XCTAssertTrue(alarm.enabled)
            XCTAssertTrue(alarm.configured)
            XCTAssertEqual(alarm.weekdays, 0x3E)
            XCTAssertEqual(alarm.volume, 50)
        }
    }

    func testDraftDaysAndVolumeSurviveRelaunchWithoutClaimingAnAppliedAlarm() throws {
        try withDefaults { defaults in
            let draft = MacAlarmPreferences(time: Date(timeIntervalSince1970: 1_700_000_000), enabled: true,
                                             weekdays: 0x41, volume: 27, configured: false)
            draft.save(to: defaults)
            XCTAssertEqual(MacAlarmPreferences.load(from: defaults), draft)
        }
    }

    func testInvalidStoredVolumeAndWeekdayBitsAreBounded() throws {
        try withDefaults { defaults in
            defaults.set(Double.infinity, forKey: "alarm.volume")
            defaults.set(255, forKey: "alarm.weekdays")
            XCTAssertEqual(MacAlarmPreferences.load(from: defaults).volume, 50)
            XCTAssertEqual(MacAlarmPreferences.load(from: defaults).weekdays, 0x7F)
            defaults.set(-4.0, forKey: "alarm.volume")
            XCTAssertEqual(MacAlarmPreferences.load(from: defaults).volume, 0)
            defaults.set(250.0, forKey: "alarm.volume")
            XCTAssertEqual(MacAlarmPreferences.load(from: defaults).volume, 100)
        }
    }

    @MainActor
    func testEditingLoadedAlarmMarksItAsDraftAndPersistsAllFields() throws {
        try withDefaults { defaults in
            MacAlarmPreferences(time: Date(timeIntervalSince1970: 1_700_000_000), enabled: true,
                                weekdays: 0x3E, volume: 50, configured: true).save(to: defaults)
            let model = AppModel(defaults: defaults, loadPairedDevices: false)
            XCTAssertTrue(model.hasConfiguredAlarm)
            XCTAssertTrue(MacAlarmPreferences.load(from: defaults).configured)
            XCTAssertEqual(MacAlarmPreferences.load(from: defaults).volume, 50)
            model.alarmWeekdays = 0x41
            model.alarmVolume = 35
            XCTAssertFalse(model.hasConfiguredAlarm)
            let reopened = AppModel(defaults: defaults, loadPairedDevices: false)
            XCTAssertEqual(reopened.alarmWeekdays, 0x41)
            XCTAssertEqual(reopened.alarmVolume, 35)
            XCTAssertFalse(reopened.hasConfiguredAlarm)
            XCTAssertFalse(reopened.bluetooth.isConnected)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "DivoomStudio.MacAlarmTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
#endif
