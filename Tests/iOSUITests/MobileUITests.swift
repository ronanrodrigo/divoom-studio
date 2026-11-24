import XCTest

@MainActor
final class MobileUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollTo(_ element: XCUIElement, app: XCUIApplication, attempts: Int = 7) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            // Scroll at the content margin: dragging across the pixel canvas paints
            // instead of scrolling, exactly as it should for an editor.
            let surface = app
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25)))
        }
    }

    func testOfflineEditorFramesAndLibrary() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Painel"].waitForExistence(timeout: 10))
        screenshot("Painel inicial offline", app: app)
        app.tabBars.buttons["Editor"].tap()
        XCTAssertTrue(app.navigationBars["Editor"].waitForExistence(timeout: 5))
        let canvas = app.descendants(matching: .any)["mobile.pixelCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)).tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)))
        screenshot("Pixels desenhados no editor", app: app)
        let addFrame = app.buttons["mobile.addFrame"]
        scrollTo(addFrame, app: app)
        XCTAssertTrue(addFrame.isHittable)
        addFrame.tap()
        let count = app.staticTexts["mobile.frameCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 3))
        XCTAssertEqual(count.value as? String, "2")
        app.buttons["mobile.duplicateFrame"].tap()
        XCTAssertEqual(count.value as? String, "3")
        let play = app.buttons["mobile.playback"]
        if !play.isHittable {
            let surface = app
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.7)))
        }
        XCTAssertTrue(play.isHittable)
        play.tap()
        XCTAssertEqual(play.label, "Pausar prévia")
        play.tap()
        screenshot("Animação com três quadros", app: app)
        app.buttons["Arquivos"].tap()
        app.buttons["Guardar na biblioteca"].tap()
        app.tabBars.buttons["Aparelho"].tap()
        let library = app.staticTexts["Biblioteca local"]
        scrollTo(library, app: app)
        library.tap()
        XCTAssertTrue(app.navigationBars["Biblioteca"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sem título-")).firstMatch.waitForExistence(timeout: 3))
        screenshot("Projeto guardado na biblioteca", app: app)
    }

    func testDeviceNavigationAndAlarmWithoutBluetooth() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Aparelho"].tap()
        XCTAssertTrue(app.navigationBars["Aparelho"].waitForExistence(timeout: 5))
        screenshot("Aparelho antes de salvar um Ditoo", app: app)
        let automatic = app.switches["mobile.automaticConnection"]
        scrollTo(automatic, app: app)
        XCTAssertTrue(automatic.isHittable, "A preferência de reconexão automática deve estar acessível.")
        let alarm = app.staticTexts["Alarme"]
        scrollTo(alarm, app: app)
        alarm.tap()
        XCTAssertTrue(app.navigationBars["Alarme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        let enabled = app.switches["Ativado"]
        XCTAssertTrue(enabled.exists)
        enabled.tap()
        let monday = app.switches["Segunda"]
        XCTAssertTrue(monday.exists)
        let previous = monday.value as? String
        monday.tap()
        let changed = NSPredicate { _, _ in (monday.value as? String) != previous }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 2) != .completed {
            monday.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertNotEqual(monday.value as? String, previous, "The weekday switch must actually change state")
        let send = app.buttons["Enviar alarme ao Ditoo"]
        scrollTo(send, app: app)
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled, "Offline must not allow alarm transmission")
        screenshot("Formulário de alarme offline", app: app)
    }

    func testAccessibilityTextSizeAndWeatherSearchField() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Painel"].waitForExistence(timeout: 10))
        screenshot("Painel com texto de acessibilidade", app: app)
        let city = app.textFields["Cidade"]
        scrollTo(city, app: app)
        XCTAssertTrue(city.isHittable)
        XCTAssertEqual(city.value as? String, "Joinville")
        XCTAssertTrue(app.buttons["Buscar"].exists)
        screenshot("Busca de cidade com texto ampliado", app: app)
        // No weather request, BLE scan, connection, or transmission is started by this test.
    }
}
