import XCTest

/// Opt-in diagnostic workflows for a physical iPhone. The observation test
/// performs no BLE actions; the separate connection test explicitly scans and
/// connects in diagnostic mode. Neither selects a protocol or sends app commands.
@MainActor
final class BluetoothDiagnosticUITests: XCTestCase {
    func testReadCurrentBluetoothDiagnostics() throws {
        guard enabled("DIVOOM_BLE_UI_DIAGNOSTIC") else {
            throw XCTSkip("Set DIVOOM_BLE_UI_DIAGNOSTIC=1 only when collecting the connected iPhone's current diagnostics.")
        }
        continueAfterFailure = true
        let app = XCUIApplication(bundleIdentifier: "dev.ronanrodrigo.DivoomStudioMobile")
        app.activate() // Preserve the existing process/logs; do not terminate or relaunch.
        capture("Estado inicial", app: app)
        let deviceTab = app.tabBars.buttons["Aparelho"]
        guard deviceTab.waitForExistence(timeout: 10) else {
            capture("Aba indisponível — verifique bloqueio do iPhone", app: app)
            XCTFail("A interface do app não ficou acessível. O iPhone pode estar bloqueado ou o app indisponível.")
            return
        }
        deviceTab.tap()
        capture("Aparelho — status e dispositivos já encontrados", app: app)
        let diagnostics = app.staticTexts["Diagnóstico Bluetooth"]
        for _ in 0..<5 {
            if diagnostics.exists && diagnostics.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        guard diagnostics.exists && diagnostics.isHittable else {
            capture("Diagnóstico não visível — estado final", app: app)
            XCTFail("Não foi possível abrir o diagnóstico; árvores e screenshots foram anexadas.")
            return
        }
        diagnostics.tap()
        capture("Diagnóstico — início do registro", app: app)
        // Capture additional log windows regardless of success/failure or whether
        // any peripheral was discovered. No control from the device is invoked.
        for page in 1...4 {
            app.swipeUp()
            capture("Diagnóstico — página \(page)", app: app)
        }
    }

    func testScanAndConnectWithoutSending() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Bluetooth connection diagnostics require a physical iPhone.")
        #else
        guard enabled("DIVOOM_BLE_CONNECTION_DIAGNOSTIC") else {
            throw XCTSkip("Set DIVOOM_BLE_CONNECTION_DIAGNOSTIC=1 for an explicitly authorized scan/connection diagnostic.")
        }
        continueAfterFailure = true
        let app = XCUIApplication(bundleIdentifier: "dev.ronanrodrigo.DivoomStudioMobile")
        // This reproduction intentionally starts a fresh session after installing
        // the fix. Unlike observation, preservation of old in-memory logs is not required.
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 12) else {
            capture("Conexão — app não ficou em primeiro plano", app: app)
            XCTFail("O iPhone não manteve o Studio em primeiro plano. Não interaja com outros apps durante este diagnóstico.")
            return
        }
        let readyTabBar = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: app.tabBars.firstMatch)
        guard XCTWaiter.wait(for: [readyTabBar], timeout: 10) == .completed,
              app.windows.firstMatch.exists,
              app.windows.firstMatch.frame.minX <= 1,
              app.windows.firstMatch.frame.width >= app.frame.width * 0.95 else {
            capture("Conexão — janela em transição ou seletor de apps", app: app)
            XCTFail("A janela não ocupou a tela; o seletor de apps ou um alerta externo pode estar ativo.")
            return
        }
        capture("Conexão — estado inicial", app: app)
        defer { capture("Conexão — estado final", app: app); captureExistingLogs(app: app) }
        let deviceTab = app.tabBars.buttons["Aparelho"]
        guard deviceTab.waitForExistence(timeout: 10) else {
            XCTFail("A interface não ficou acessível; verifique o bloqueio do iPhone.")
            return
        }
        deviceTab.tap()
        capture("Conexão — antes da busca", app: app)
        // Do not change the user's protocol selection. The diagnostic default
        // permits GATT discovery/notifications but never application-data writes.
        let profile = app.descendants(matching: .any)["mobile.protocolSelection"].firstMatch
        let profileDescription = profile.exists ? profile.label + " " + String(describing: profile.value ?? "") : ""
        guard profileDescription.contains("Somente diagnóstico") else {
            throw XCTSkip("O perfil atual não é Somente diagnóstico; nenhum perfil foi alterado e nenhuma conexão foi iniciada.")
        }
        if app.buttons["Desconectar"].exists {
            capture("Conexão — aparelho já conectado em diagnóstico", app: app)
            return
        }
        let scan = app.buttons["Buscar"]
        for _ in 0..<5 {
            if scan.exists && scan.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.75)))
        }
        guard scan.exists && scan.isHittable else {
            capture("Conexão — Buscar indisponível mesmo após rolar ao topo", app: app)
            XCTFail("Botão Buscar indisponível.")
            return
        }
        scan.tap()
        let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "mobile.bleCandidate."))
        guard candidates.firstMatch.waitForExistence(timeout: 18) else {
            capture("Conexão — nenhum candidato encontrado", app: app)
            app.buttons["Parar busca"].tap()
            XCTFail("Nenhum anúncio ou periférico já conectado foi encontrado; diagnóstico anexado.")
            return
        }
        capture("Conexão — candidatos descobertos", app: app)
        app.buttons["Parar busca"].tap()
        let named = candidates.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ditoo"))
        let compatible = candidates.matching(NSPredicate(format: "label BEGINSWITH %@", "BLE com serviço compatível"))
        let selected: XCUIElement
        if named.count == 1 { selected = named.element(boundBy: 0) }
        else if named.count == 0 && compatible.count == 1 { selected = compatible.element(boundBy: 0) }
        else { XCTFail("Candidatos ausentes ou ambíguos; nenhum aparelho foi escolhido automaticamente."); return }
        guard selected.isHittable else { XCTFail("O candidato encontrado está fora da área visível; diagnóstico anexado."); return }
        selected.tap()
        let connect = app.buttons["Conectar"]
        guard connect.exists && connect.isEnabled else { XCTFail("Botão Conectar indisponível após seleção."); return }
        connect.tap()
        let disconnectedAction = app.buttons["Desconectar"]
        let connected = disconnectedAction.waitForExistence(timeout: 25)
        capture("Conexão — resultado sem comandos", app: app)
        XCTAssertTrue(connected, "A conexão BLE não concluiu; consulte status e registro anexados.")
        // Deliberately leave the diagnostic connection as observed. Do not invoke
        // controls, dashboard, pixel upload, animation, time sync, or alarms.
        #endif
    }

    private func enabled(_ key: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment[key] == "1" || environment["TEST_RUNNER_" + key] == "1"
    }

    private func captureExistingLogs(app: XCUIApplication) {
        let deviceTab = app.tabBars.buttons["Aparelho"]
        guard deviceTab.exists else { return }
        deviceTab.tap()
        let diagnostics = app.staticTexts["Diagnóstico Bluetooth"]
        for _ in 0..<6 {
            if diagnostics.exists && diagnostics.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
        }
        guard diagnostics.exists && diagnostics.isHittable else { capture("Conexão — diagnóstico não acessível", app: app); return }
        diagnostics.tap()
        capture("Conexão — registro inicial", app: app)
        for page in 1...4 { app.swipeUp(); capture("Conexão — registro página \(page)", app: app) }
    }

    private func capture(_ title: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = title
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(title) — árvore de acessibilidade"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
