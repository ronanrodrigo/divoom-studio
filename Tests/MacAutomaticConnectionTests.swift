#if os(macOS)
import XCTest
@testable import DivoomStudio

final class MacAutomaticConnectionTests: XCTestCase {
    private let fixtureAddress = "02:00:00:00:00:01"

    func testDefaultPreferenceCannotReconnectWithoutSuccessfulTarget() throws {
        try withDefaults { defaults in
            let preferences = RFCOMMConnectionPreferences.load(from: defaults)
            XCTAssertTrue(preferences.enabled)
            XCTAssertNil(preferences.device)
            XCTAssertFalse(preferences.mayReconnect)
        }
    }

    func testSuccessfulTargetChannelAndDisabledPreferenceRoundTrip() throws {
        try withDefaults { defaults in
            let device = RememberedRFCOMMDevice(address: fixtureAddress, name: "Test Ditoo", channel: 3)
            let preferences = RFCOMMConnectionPreferences(enabled: true, device: device)
            preferences.save(to: defaults)
            XCTAssertEqual(RFCOMMConnectionPreferences.load(from: defaults), preferences)
            RFCOMMConnectionPreferences(enabled: false, device: device).save(to: defaults)
            let disabled = RFCOMMConnectionPreferences.load(from: defaults)
            XCTAssertEqual(disabled.device?.channel, 3)
            XCTAssertEqual(disabled.device?.address, fixtureAddress)
            XCTAssertFalse(disabled.mayReconnect)
        }
    }

    func testCorruptOrInvalidTargetNeverBecomesAutomaticDestination() throws {
        try withDefaults { defaults in
            defaults.set(Data("not-json".utf8), forKey: "mac.bluetooth.automatic.device")
            XCTAssertFalse(RFCOMMConnectionPreferences.load(from: defaults).mayReconnect)
            for device in [
                RememberedRFCOMMDevice(address: "bad-address", name: "Test", channel: 1),
                RememberedRFCOMMDevice(address: fixtureAddress, name: "Test", channel: 0),
                RememberedRFCOMMDevice(address: fixtureAddress, name: "Test", channel: 31)
            ] {
                RFCOMMConnectionPreferences(enabled: true, device: device).save(to: defaults)
                let loaded = RFCOMMConnectionPreferences.load(from: defaults)
                XCTAssertNil(loaded.device)
                XCTAssertFalse(loaded.mayReconnect)
            }
        }
    }

    func testAddressNormalizationAndValidation() {
        XCTAssertEqual(RFCOMMConnectionPreferences.normalizedAddress(" 02-aa-bb-cc-dd-ef \n"), "02:AA:BB:CC:DD:EF")
        XCTAssertNil(RFCOMMConnectionPreferences.normalizedAddress("02:00:00:00:00"))
        XCTAssertNil(RFCOMMConnectionPreferences.normalizedAddress("GG:00:00:00:00:00"))
        XCTAssertNil(RFCOMMConnectionPreferences.normalizedAddress("2:0:0:0:0:1"))
    }

    func testBackoffSaturatesAtOneMinuteAndSuccessResetsIt() {
        var backoff = RFCOMMReconnectBackoff()
        XCTAssertEqual((0..<10).map { _ in backoff.nextDelay() }, [1, 2, 4, 8, 15, 30, 60, 60, 60, 60])
        for _ in 0..<1000 { XCTAssertEqual(backoff.nextDelay(), 60) }
        backoff.reset()
        XCTAssertEqual(backoff.nextDelay(), 1)
    }

    func testOldCallbackEpochCannotAffectReusedChannelIdentity() {
        let first = NSObject()
        let second = NSObject()
        let oldEpoch = UUID()
        let newEpoch = UUID()
        let callback = RFCOMMCallbackScope(epoch: oldEpoch, channelID: ObjectIdentifier(first))
        XCTAssertTrue(callback.isCurrent(epoch: oldEpoch, channelID: ObjectIdentifier(first)))
        XCTAssertFalse(callback.isCurrent(epoch: newEpoch, channelID: ObjectIdentifier(first)), "Even a reused channel identity must reject an old session")
        XCTAssertFalse(callback.isCurrent(epoch: oldEpoch, channelID: ObjectIdentifier(second)))
        XCTAssertFalse(callback.isCurrent(epoch: newEpoch, channelID: ObjectIdentifier(second)))
    }

    @MainActor
    func testLegacySelectionIsNotMigratedToSuccessfulTarget() throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(fixtureAddress, forKey: "divoom.address")
        let controller = BluetoothController(defaults: defaults, loadPairedDevices: false)
        XCTAssertEqual(controller.selectedAddress, fixtureAddress)
        XCTAssertNil(controller.rememberedDeviceName)
        XCTAssertTrue(controller.automaticConnectionEnabled)
        XCTAssertTrue(controller.devices.isEmpty)
        controller.startAutomaticConnection() // no saved success: returns before any Bluetooth API
        XCTAssertFalse(controller.isConnected)
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.logs.isEmpty)
    }

    @MainActor
    func testManualDisconnectDisablesPreferenceWithoutForgettingTarget() throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let target = RememberedRFCOMMDevice(address: fixtureAddress, name: "Test Ditoo", channel: 1)
        RFCOMMConnectionPreferences(enabled: true, device: target).save(to: defaults)
        let controller = BluetoothController(defaults: defaults, loadPairedDevices: false)
        XCTAssertEqual(controller.rememberedDeviceName, "Test Ditoo")
        XCTAssertTrue(controller.logs.isEmpty, "Loading preferences does not connect")
        controller.disconnect()
        controller.startAutomaticConnection() // explicit opt-out must remain effective
        XCTAssertFalse(controller.automaticConnectionEnabled)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(RFCOMMConnectionPreferences.load(from: defaults).device, target)
        XCTAssertFalse(RFCOMMConnectionPreferences.load(from: defaults).enabled)
        controller.selectedAddress = "invalid"
        controller.connect() // rejects before hardware; does not silently enable the preference
        XCTAssertFalse(controller.automaticConnectionEnabled)
    }

    @MainActor
    func testForgetRemovesTargetAndLegacySelectionWithoutHardware() throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        RFCOMMConnectionPreferences(enabled: true, device: RememberedRFCOMMDevice(address: fixtureAddress, name: "Test Ditoo", channel: 1)).save(to: defaults)
        defaults.set(fixtureAddress, forKey: "divoom.address")
        let controller = BluetoothController(defaults: defaults, loadPairedDevices: false)
        controller.forgetDevice()
        controller.startAutomaticConnection()
        XCTAssertNil(controller.rememberedDeviceName)
        XCTAssertEqual(controller.selectedAddress, "")
        XCTAssertNil(defaults.string(forKey: "divoom.address"))
        XCTAssertFalse(RFCOMMConnectionPreferences.load(from: defaults).mayReconnect)
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor
    func testSleepCleanupPreservesPreferenceAndSavedTarget() throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let target = RememberedRFCOMMDevice(address: fixtureAddress, name: "Test Ditoo", channel: 1)
        RFCOMMConnectionPreferences(enabled: true, device: target).save(to: defaults)
        let controller = BluetoothController(defaults: defaults, loadPairedDevices: false)
        controller.prepareForSleep()
        controller.prepareForSleep() // repeated sleep notifications are harmless
        XCTAssertTrue(controller.automaticConnectionEnabled)
        XCTAssertEqual(RFCOMMConnectionPreferences.load(from: defaults).device, target)
        XCTAssertFalse(controller.isConnected)
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.logs.isEmpty)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let domain = "DivoomStudio.MacAutoTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: domain)), domain)
    }
    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        try test(defaults)
    }
}
#endif
