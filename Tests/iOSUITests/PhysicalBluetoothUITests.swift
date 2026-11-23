import XCTest

/// Opt-in only. Standard scripts never scan or connect to real Bluetooth hardware.
@MainActor
final class PhysicalBluetoothUITests: XCTestCase {
    func testExplicitDitooConnectionAndImage() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DIVOOM_BLE_HARDWARE_TEST"] == "1",
                          "Requires an explicit physical-device test request")
        #if targetEnvironment(simulator)
        throw XCTSkip("A simulator cannot validate the physical Ditoo")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Aparelho"].tap()
        app.buttons["Buscar"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Permitir", "Allow", "OK"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let device = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ditoo")).firstMatch
        XCTAssertTrue(device.waitForExistence(timeout: 20), "Nenhum Ditoo BLE descoberto; confira canal Light e conexão do Mac/app oficial")
        device.tap()
        let picker = app.buttons["Protocolo"]
        if picker.exists { picker.tap() }
        else { app.cells.containing(.staticText, identifier: "Protocolo").firstMatch.tap() }
        let profile = app.buttons["Controlar Ditoo Plus (experimental)"]
        if profile.exists { profile.tap() }
        else { app.staticTexts["Controlar Ditoo Plus (experimental)"].firstMatch.tap() }
        app.buttons["Conectar"].tap()
        XCTAssertTrue(app.buttons["Desconectar"].waitForExistence(timeout: 20))
        let connected = XCTAttachment(screenshot: app.screenshot())
        connected.name = "Ditoo físico conectado por BLE"
        connected.lifetime = .keepAlways
        add(connected)
        app.tabBars.buttons["Editor"].tap()
        let canvas = app.descendants(matching: .any)["mobile.pixelCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.75)))
        let send = app.buttons["Enviar quadro"]
        for _ in 0..<6 where !send.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25)))
        }
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "bytes enviados")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 15), "Sem confirmação do fluxo de envio; consulte o diagnóstico")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Envio BLE físico; confirmação visual depende do usuário"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }
}
