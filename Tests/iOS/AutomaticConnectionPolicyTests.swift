import XCTest
@testable import DivoomStudioMobile

final class AutomaticConnectionPolicyTests: XCTestCase {
    func testDefaultPreferenceDoesNotAuthorizeAnUnknownTarget() throws {
        try withDefaults { defaults in
            let preferences = BLEAutomaticPreferences.load(from: defaults)
            XCTAssertTrue(preferences.enabled)
            XCTAssertNil(preferences.device)
            XCTAssertFalse(preferences.mayReconnect)
            XCTAssertFalse(preferences.allowsRestoration(of: UUID()))
        }
    }

    func testRememberedTargetAndStableProfilePersistLocally() throws {
        try withDefaults { defaults in
            let target = RememberedBLEDevice(id: UUID(), name: "Test Ditoo", selection: .ditooPlusRCSP)
            let preferences = BLEAutomaticPreferences(enabled: true, device: target)
            preferences.save(to: defaults)
            let restored = BLEAutomaticPreferences.load(from: defaults)
            XCTAssertEqual(restored, preferences)
            XCTAssertEqual(restored.device?.selection, .ditooPlusRCSP)
            XCTAssertEqual(restored.device?.protocolIdentifier, "ditoo-plus-rcsp")
            XCTAssertTrue(restored.allowsRestoration(of: target.id))
            XCTAssertFalse(restored.allowsRestoration(of: UUID()), "A restored stranger is never automatically adopted")
        }
    }

    func testExplicitDisableSurvivesRelaunchAndRejectsRestoration() throws {
        try withDefaults { defaults in
            let target = RememberedBLEDevice(id: UUID(), name: "Test Ditoo", selection: .diagnostic)
            BLEAutomaticPreferences(enabled: false, device: target).save(to: defaults)
            let restored = BLEAutomaticPreferences.load(from: defaults)
            XCTAssertFalse(restored.enabled)
            XCTAssertEqual(restored.device, target)
            XCTAssertFalse(restored.mayReconnect)
            XCTAssertFalse(restored.allowsRestoration(of: target.id))
        }
    }

    func testMalformedSavedTargetDoesNotBecomeAnAutomaticConnection() throws {
        try withDefaults { defaults in
            defaults.set(Data("invalid-json".utf8), forKey: "bluetooth.automaticConnection.rememberedDevice")
            let restored = BLEAutomaticPreferences.load(from: defaults)
            XCTAssertNil(restored.device)
            XCTAssertFalse(restored.mayReconnect)
        }
    }

    func testFailureBackoffSaturatesAtOneMinuteAndResetsAfterSuccess() {
        var backoff = BLEReconnectBackoff()
        XCTAssertEqual((0..<10).map { _ in backoff.nextDelay() }, [1, 2, 4, 8, 15, 30, 60, 60, 60, 60])
        for _ in 0..<1000 { XCTAssertEqual(backoff.nextDelay(), 60) }
        backoff.reset()
        XCTAssertEqual(backoff.nextDelay(), 1)
    }

    @MainActor
    func testControllerConstructionOnlyLoadsPreferencesAndForgetClearsTarget() throws {
        let suiteName = "DivoomStudio.AutoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let target = RememberedBLEDevice(id: UUID(), name: "Test Ditoo", selection: .ditooPlusRCSP)
        BLEAutomaticPreferences(enabled: false, device: target).save(to: defaults)
        let controller = MobileBluetoothController(defaults: defaults)
        XCTAssertEqual(controller.rememberedDeviceName, "Test Ditoo")
        XCTAssertFalse(controller.automaticConnectionEnabled)
        XCTAssertFalse(controller.isConnected)
        XCTAssertFalse(controller.isBusy)
        XCTAssertFalse(controller.isScanning)
        XCTAssertTrue(controller.logs.isEmpty)
        controller.startAutomaticConnection() // disabled: must not create a manager or begin any operation
        XCTAssertTrue(controller.logs.isEmpty)
        controller.forgetDevice()
        XCTAssertNil(controller.rememberedDeviceName)
        XCTAssertNil(BLEAutomaticPreferences.load(from: defaults).device)
        XCTAssertFalse(BLEAutomaticPreferences.load(from: defaults).enabled)
    }

    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suiteName = "DivoomStudio.AutoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try test(defaults)
    }
}
