import Foundation
import Observation
@preconcurrency import CoreBluetooth

struct MobileDivoomDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
}

struct MobileBluetoothLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date = Date()
    let direction: String
    let message: String
}

/// CoreBluetooth objects are delivered on DispatchQueue.main. The bridge only transfers
/// ownership of a reference to MainActor; no mutable CB object is used on another queue.
private struct MainQueueCBReference<Value: AnyObject>: @unchecked Sendable { let value: Value }

@MainActor
@Observable
final class MobileBluetoothController: NSObject, CBCentralManagerDelegate {
    private(set) var devices: [MobileDivoomDevice] = []
    var selectedDeviceID: UUID?
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var isScanning = false
    private(set) var isDisconnecting = false
    private(set) var status = "Bluetooth ainda não iniciado"
    private(set) var logs: [MobileBluetoothLogEntry] = []
    private(set) var profileDescription = "Perfil BLE ainda não identificado"
    var profileSelection: BLEProtocolSelection = .diagnostic
    private(set) var notificationsReady = false
    var canSend: Bool { isConnected && profileSelection == .ditooPlusRCSP && profile != nil && notificationsReady && writeCharacteristic != nil }
    var compatibilityStatus: String {
        if profile == nil { return "Perfil GATT não confirmado; envio desabilitado." }
        if profileSelection == .diagnostic { return "Escolha BLE RCSP experimental para testar comandos neste Ditoo-Plus." }
        return "BLE RCSP fundamentado em teste público Ditoo-Plus; este aparelho ainda requer validação física."
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var profile: BLEProfile?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var notifyCharacteristic: CBCharacteristic?
    @ObservationIgnored private var pendingServices: Set<String> = []
    @ObservationIgnored private var sessionGate = BLESessionGate()
    @ObservationIgnored private var peripheralDelegate: EpochPeripheralDelegate?
    private var generation: UUID { sessionGate.epoch }
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTimeout: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var transferTimeout: Task<Void, Never>?
    @ObservationIgnored private var writeTimeout: Task<Void, Never>?
    @ObservationIgnored private var pendingWrite: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var readinessWaiter: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var parser = DivoomFrameParser()
    @ObservationIgnored private var packetNumber = UInt32.random(in: 1_048_576...1_073_741_824)
    @ObservationIgnored private var expectedPacket: UInt32?
    @ObservationIgnored private var receivedPacketACK = false
    @ObservationIgnored private var packetWaiter: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var packetTimeout: Task<Void, Never>?
    @ObservationIgnored private var awaitingAnimationReady = false
    @ObservationIgnored private var animationReadyReceived = false
    @ObservationIgnored private var animationReadyWaiter: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var animationReadyTimeout: Task<Void, Never>?

    enum TransportError: Error, LocalizedError {
        case disconnected, timeout, unsupportedProfile, writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .disconnected: "Conexão BLE encerrada."
            case .timeout: "O aparelho não concluiu a operação no tempo esperado."
            case .unsupportedProfile: "Perfil BLE sem compatibilidade confirmada com os comandos Ditoo-Plus."
            case .writeFailed(let message): "Falha BLE: \(message)"
            }
        }
    }

    // Deliberately no manager, scan, connect, restore or commands in init.
    override init() { super.init() }

    isolated deinit {
        scanTask?.cancel()
        connectionTimeout?.cancel()
        sendTask?.cancel()
        transferTimeout?.cancel()
        writeTimeout?.cancel()
        packetTimeout?.cancel()
        animationReadyTimeout?.cancel()
        animationReadyWaiter?.resume(throwing: CancellationError())
        pendingWrite?.resume(throwing: CancellationError())
        readinessWaiter?.resume(throwing: CancellationError())
        packetWaiter?.resume(throwing: CancellationError())
        central?.stopScan()
        peripheral?.delegate = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        central?.delegate = nil
    }

    func scan() {
        guard !isBusy, !isConnected else { return }
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else { beginScanIfReady() }
    }

    private func beginScanIfReady() {
        guard wantsScan, let central else { return }
        guard central.state == .poweredOn else { status = Self.stateDescription(central.state); return }
        scanTask?.cancel()
        devices = []
        selectedDeviceID = nil
        peripherals = [:]
        isScanning = true
        status = "Buscando aparelhos Divoom próximos…"
        // No UUID filter: older Ditoo-light advertisements may omit a service UUID.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        wantsScan = false
        scanTask?.cancel()
        scanTask = nil
        central?.stopScan()
        isScanning = false
        if !isConnected && !isBusy { status = devices.isEmpty ? "Nenhum Divoom encontrado. Ligue-o e libere a conexão do outro aparelho." : "Selecione um aparelho para conectar." }
    }

    func connect() {
        guard sessionGate.mayConnect, !isDisconnecting else {
            status = "Aguardando o Bluetooth concluir a desconexão anterior."
            return
        }
        guard !isBusy, !isConnected, let central, central.state == .poweredOn,
              let selectedDeviceID, let selected = peripherals[selectedDeviceID] else {
            status = "Busque e selecione um aparelho BLE primeiro."
            return
        }
        stopScan()
        resetConnection(cancelPeripheral: true)
        guard let attempt = sessionGate.begin(deviceID: selected.identifier) else { return }
        peripheral = selected
        let proxy = EpochPeripheralDelegate(epoch: attempt) { [weak self] epoch, id, event in
            Task { @MainActor [weak self] in self?.receivePeripheralEvent(event, epoch: epoch, deviceID: id) }
        }
        peripheralDelegate = proxy
        selected.delegate = proxy
        isBusy = true
        status = "Conectando e identificando serviços BLE…"
        central.connect(selected, options: nil)
        connectionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == attempt, self.isBusy else { return }
            self.log("ERRO", "Conexão/descoberta expirou após 15 segundos; sem repetição.")
            self.resetConnection(cancelPeripheral: true)
            self.status = "A conexão ou descoberta BLE expirou."
        }
    }

    func disconnect() {
        stopScan()
        resetConnection(cancelPeripheral: true)
        status = isDisconnecting ? "Aguardando o Bluetooth concluir a desconexão…" : "Desconectado"
    }

    private func resetConnection(cancelPeripheral: Bool) {
        // Invalidating the peripheral epoch happens before cancelling any continuation.
        // Do not clear an already-pending cancellation when Disconnect is pressed again.
        if cancelPeripheral, let peripheral {
            if peripheral.state != .disconnected {
                sessionGate.cancel()
                isDisconnecting = sessionGate.cancellingDeviceID != nil
            } else {
                sessionGate.invalidate()
                isDisconnecting = false
                // A terminal callback may already be queued on this old manager.
                discardCentralManager()
            }
        } else if !cancelPeripheral || sessionGate.cancellingDeviceID == nil {
            sessionGate.invalidate()
            isDisconnecting = false
        }
        connectionTimeout?.cancel(); connectionTimeout = nil
        sendTask?.cancel(); sendTask = nil
        transferTimeout?.cancel(); transferTimeout = nil
        writeTimeout?.cancel(); writeTimeout = nil
        packetTimeout?.cancel(); packetTimeout = nil
        animationReadyTimeout?.cancel(); animationReadyTimeout = nil
        animationReadyWaiter?.resume(throwing: TransportError.disconnected); animationReadyWaiter = nil
        awaitingAnimationReady = false
        animationReadyReceived = false
        packetWaiter?.resume(throwing: TransportError.disconnected); packetWaiter = nil
        expectedPacket = nil
        receivedPacketACK = false
        notificationsReady = false
        pendingWrite?.resume(throwing: TransportError.disconnected); pendingWrite = nil
        readinessWaiter?.resume(throwing: TransportError.disconnected); readinessWaiter = nil
        if let peripheral {
            peripheral.delegate = nil
            if cancelPeripheral { central?.cancelPeripheralConnection(peripheral) }
        }
        peripheral = nil
        peripheralDelegate = nil
        profile = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingServices = []
        isConnected = false
        isBusy = false
        profileDescription = "Perfil BLE ainda não identificado"
        parser.reset()
    }

    func send(_ payloads: [Data], label: String) {
        // Bulk animation needs the announce/request gate; never send old 0x49 or raw 0x8B here.
        guard payloads.allSatisfy({ $0.first != 0x49 && $0.first != 0x8B }) else {
            status = "Use Enviar animação para a transferência BLE específica do Ditoo-Plus."
            log("INFO", status)
            return
        }
        beginTransfer(payloads, label: label, requiresAnimationReady: false)
    }

    func sendAnimation(frames: [[UInt8]], durationMilliseconds: Int) {
        guard !isBusy else { return }
        do {
            let transfer = try BLEProfile.animationPayloads(frames: frames, durationMilliseconds: durationMilliseconds)
            beginTransfer([transfer.announce] + transfer.chunks, label: "Animação BLE", requiresAnimationReady: true)
        } catch {
            status = "Não foi possível preparar a animação (2–60 quadros, duração 1–65535 ms, até 48 KB): \(error.localizedDescription)"
            log("ERRO", status)
        }
    }

    private func beginTransfer(_ payloads: [Data], label: String, requiresAnimationReady: Bool) {
        guard canSend else {
            status = "Envio bloqueado: o perfil BLE deste aparelho precisa de confirmação. Exporte o diagnóstico."
            log("INFO", status)
            return
        }
        guard !isBusy, !payloads.isEmpty, payloads.count <= 256,
              payloads.allSatisfy({ !$0.isEmpty && $0.count <= 60_000 }) else { return }
        awaitingAnimationReady = requiresAnimationReady
        animationReadyReceived = false
        let attempt = generation
        isBusy = true
        status = "Enviando \(label)…"
        transferTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, self.generation == attempt, self.isBusy else { return }
            self.log("ERRO", "Envio excedeu 60 segundos; conexão encerrada, sem repetição.")
            self.resetConnection(cancelPeripheral: true)
            self.status = "Envio expirou após 60 segundos."
        }
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                for (payloadIndex, payload) in payloads.enumerated() {
                    self.packetNumber &+= 1
                    let number = self.packetNumber
                    let frame = try BLEProfile.rcspEnvelope(BLEProfile.prepareCommandPayload(payload), packetNumber: number)
                    self.expectedPacket = number
                    self.receivedPacketACK = false
                    try Task.checkCancellation()
                    guard self.generation == attempt, self.profileSelection == .ditooPlusRCSP, let peripheral = self.peripheral,
                          let characteristic = self.writeCharacteristic else { throw TransportError.disconnected }
                    let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                    let capacity = min(138, peripheral.maximumWriteValueLength(for: type))
                    guard capacity > 0 else { throw TransportError.unsupportedProfile }
                    for offset in stride(from: 0, to: frame.count, by: capacity) {
                        try Task.checkCancellation()
                        guard self.generation == attempt, self.profileSelection == .ditooPlusRCSP else { throw TransportError.disconnected }
                        let chunk = frame.subdata(in: offset..<min(offset + capacity, frame.count))
                        try await self.write(chunk, type: type)
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    self.log("TX", Self.hex(frame))
                    if !self.receivedPacketACK {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                            self.packetWaiter = continuation
                            self.packetTimeout = Task { [weak self] in
                                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                                guard let self, self.expectedPacket == number else { return }
                                let pending = self.packetWaiter; self.packetWaiter = nil
                                pending?.resume(throwing: TransportError.timeout)
                            }
                        }
                    }
                    self.packetTimeout?.cancel(); self.packetTimeout = nil
                    self.expectedPacket = nil
                    if requiresAnimationReady && payloadIndex == 0 {
                        if !self.animationReadyReceived {
                            self.status = "Aguardando pedido de dados da animação…"
                            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                                self.animationReadyWaiter = continuation
                                self.animationReadyTimeout = Task { [weak self] in
                                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                                    guard let self, self.generation == attempt, self.awaitingAnimationReady else { return }
                                    let pending = self.animationReadyWaiter; self.animationReadyWaiter = nil
                                    pending?.resume(throwing: TransportError.timeout)
                                }
                            }
                        }
                        self.animationReadyTimeout?.cancel(); self.animationReadyTimeout = nil
                        self.awaitingAnimationReady = false
                        self.status = "Enviando quadros da animação…"
                    }
                }
                guard self.generation == attempt else { return }
                self.status = "\(label): bytes enviados; confira o aparelho. Resposta BLE não prova resultado visual."
                self.finishTransfer()
            } catch {
                guard self.generation == attempt else { return }
                self.log("ERRO", error.localizedDescription)
                self.resetConnection(cancelPeripheral: true)
                self.status = "Envio interrompido: \(error.localizedDescription)"
            }
        }
    }

    private func write(_ data: Data, type: CBCharacteristicWriteType) async throws {
        guard let peripheral, let characteristic = writeCharacteristic else { throw TransportError.disconnected }
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
            try await withCheckedThrowingContinuation { continuation in
                readinessWaiter = continuation
                scheduleWriteTimeout()
            }
            writeTimeout?.cancel(); writeTimeout = nil
            try Task.checkCancellation()
        }
        if type == .withResponse {
            try await withCheckedThrowingContinuation { continuation in
                pendingWrite = continuation
                scheduleWriteTimeout()
                peripheral.writeValue(data, for: characteristic, type: type)
            }
        } else {
            peripheral.writeValue(data, for: characteristic, type: type)
        }
    }

    private func scheduleWriteTimeout() {
        writeTimeout?.cancel()
        let attempt = generation
        writeTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.generation == attempt else { return }
            self.pendingWrite?.resume(throwing: TransportError.timeout); self.pendingWrite = nil
            self.readinessWaiter?.resume(throwing: TransportError.timeout); self.readinessWaiter = nil
        }
    }

    private func finishTransfer() {
        transferTimeout?.cancel(); transferTimeout = nil
        writeTimeout?.cancel(); writeTimeout = nil
        animationReadyTimeout?.cancel(); animationReadyTimeout = nil
        awaitingAnimationReady = false
        animationReadyReceived = false
        isBusy = false
        sendTask = nil
    }

    func exportLog() -> String {
        let formatter = ISO8601DateFormatter()
        return logs.map { "\(formatter.string(from: $0.date)) [\($0.direction)] \($0.message)" }.joined(separator: "\n")
    }

    private func log(_ direction: String, _ message: String) {
        logs.append(MobileBluetoothLogEntry(direction: direction, message: message))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    private func connected(_ id: UUID) {
        guard let peripheral, peripheral.identifier == id else { return }
        log("INFO", "Conexão GATT estabelecida; descobrindo serviços, sem comandos automáticos.")
        peripheral.discoverServices(nil)
    }

    private func servicesDiscovered(_ id: UUID, error: String?) {
        guard let peripheral, peripheral.identifier == id else { return }
        if let error { failDiscovery(error); return }
        let services = peripheral.services ?? []
        pendingServices = Set(services.map { $0.uuid.uuidString })
        for service in services {
            log("GATT", "Serviço \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
        if services.isEmpty { finishDiscovery() }
    }

    private func characteristicsDiscovered(_ id: UUID, serviceUUID: String, error: String?) {
        guard let peripheral, peripheral.identifier == id,
              let service = peripheral.services?.first(where: { $0.uuid.uuidString == serviceUUID }) else { return }
        if let error { failDiscovery(error); return }
        let characteristics = service.characteristics ?? []
        for characteristic in characteristics {
            log("GATT", "\(serviceUUID) / \(characteristic.uuid.uuidString) propriedades=0x\(String(characteristic.properties.rawValue, radix: 16))")
        }
        if let recognized = BLEProfile.recognized(serviceUUID: serviceUUID,
                                                   characteristicUUIDs: Set(characteristics.map { $0.uuid.uuidString })) {
            profile = recognized
            profileDescription = recognized.name
            writeCharacteristic = characteristics.first { $0.uuid.uuidString.uppercased() == recognized.writeUUID && !$0.properties.intersection([.write, .writeWithoutResponse]).isEmpty }
            notifyCharacteristic = characteristics.first { $0.uuid.uuidString.uppercased() == recognized.notifyUUID && !$0.properties.intersection([.notify, .indicate]).isEmpty }
            // Read-only diagnostics: no init/unlock or characteristic fallback guessed here.
            if let notifyCharacteristic { peripheral.setNotifyValue(true, for: notifyCharacteristic) }
        }
        pendingServices.remove(serviceUUID)
        if pendingServices.isEmpty { finishDiscovery() }
    }

    private func finishDiscovery() {
        connectionTimeout?.cancel(); connectionTimeout = nil
        isConnected = true
        isBusy = false
        if profile == nil { profileDescription = "Perfil desconhecido; características registradas no diagnóstico" }
        status = canSend ? "Conectado; aguardando ação" : "Conectado para diagnóstico. Comandos bloqueados até confirmar o protocolo deste Ditoo."
        log("INFO", status)
    }

    private func failDiscovery(_ message: String) {
        log("ERRO", message)
        resetConnection(cancelPeripheral: true)
        status = "Falha ao descobrir perfil BLE: \(message)"
    }

    private static func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "Bluetooth disponível"
        case .poweredOff: "Ative o Bluetooth nos Ajustes."
        case .unauthorized: "Permita Bluetooth para o Divoom Studio nos Ajustes."
        case .unsupported: "Este dispositivo não oferece Bluetooth compatível."
        case .resetting: "Bluetooth reiniciando; tente buscar novamente."
        case .unknown: "Aguardando o estado do Bluetooth…"
        @unknown default: "Estado Bluetooth desconhecido."
        }
    }
    private static func hex(_ data: Data) -> String { data.prefix(2048).map { String(format: "%02X", $0) }.joined(separator: " ") + (data.count > 2048 ? " …" : "") }

    private func receivePeripheralEvent(_ event: MobilePeripheralEvent, epoch: UUID, deviceID: UUID) {
        guard sessionGate.accepts(epoch: epoch, deviceID: deviceID), peripheral?.identifier == deviceID else { return }
        switch event {
        case .services(let error): servicesDiscovered(deviceID, error: error)
        case .characteristics(let service, let error): characteristicsDiscovered(deviceID, serviceUUID: service, error: error)
        case .value(let uuid, let data, let error):
            if let error { log("ERRO", error); return }
            guard let data else { return }
            log("RX", "\(uuid): \(Self.hex(data))")
            guard profileSelection == .ditooPlusRCSP else { return }
            for payload in parser.append(data) {
                if awaitingAnimationReady && BLEProfile.isAnimationReadyReply(payload) {
                    animationReadyReceived = true
                    animationReadyTimeout?.cancel(); animationReadyTimeout = nil
                    let pending = animationReadyWaiter; animationReadyWaiter = nil
                    pending?.resume()
                    log("INFO", "Aparelho solicitou os dados da animação; liberando blocos paletizados.")
                }
                if let number = BLEProfile.packetAcknowledgement(payload), number == expectedPacket {
                    receivedPacketACK = true
                    packetTimeout?.cancel(); packetTimeout = nil
                    let pending = packetWaiter; packetWaiter = nil
                    pending?.resume()
                    log("ACK", "Envelope RCSP confirmado pelo número do pacote; confira o resultado visual.")
                }
                if let command = DivoomProtocol.acknowledgedCommand(in: payload) {
                    log("ACK", String(format: "Resposta observada ao opcode 0x%02X; resultado visual não confirmado.", command))
                }
            }
        case .wrote(let uuid, let error):
            guard writeCharacteristic?.uuid.uuidString == uuid, pendingWrite != nil else { return }
            writeTimeout?.cancel(); writeTimeout = nil
            let continuation = pendingWrite; pendingWrite = nil
            if let error { continuation?.resume(throwing: TransportError.writeFailed(error)) } else { continuation?.resume() }
        case .ready:
            guard readinessWaiter != nil else { return }
            writeTimeout?.cancel(); writeTimeout = nil
            readinessWaiter?.resume(); readinessWaiter = nil
        case .notification(let uuid, let notifying, let error):
            guard notifyCharacteristic?.uuid.uuidString == uuid else { return }
            notificationsReady = error == nil && notifying
            if isConnected { status = canSend ? "BLE RCSP pronto; envio somente por ação explícita." : "Conectado para diagnóstico; escolha o protocolo para testar." }
            log(error == nil ? "GATT" : "ERRO", "Notificações \(uuid): \(notifying); \(error ?? "sem erro")")
        }
    }

    private func terminalConnectionEvent(deviceID: UUID, message: String, managerID: ObjectIdentifier) {
        guard let central, ObjectIdentifier(central) == managerID else { return }
        if sessionGate.finishCancellation(deviceID: deviceID) {
            isDisconnecting = false
            discardCentralManager()
            status = "Desconectado. Busque o aparelho novamente para iniciar uma nova sessão."
            log("INFO", status)
            return
        }
        guard peripheral?.identifier == deviceID else { return }
        resetConnection(cancelPeripheral: false)
        discardCentralManager()
        status = message
        log("INFO", message)
    }

    private func discardCentralManager() {
        wantsScan = false
        scanTask?.cancel()
        scanTask = nil
        central?.stopScan()
        isScanning = false
        central?.delegate = nil
        central = nil
        peripherals = [:]
        devices = []
        selectedDeviceID = nil
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let rawState = central.state.rawValue
        let managerReference = MainQueueCBReference(value: central)
        Task { @MainActor [weak self] in
            guard let self, let current = self.central, ObjectIdentifier(current) == ObjectIdentifier(managerReference.value),
                  let state = CBManagerState(rawValue: rawState) else { return }
            self.status = Self.stateDescription(state)
            if state == .poweredOn { self.beginScanIfReady() }
            else if state != .unknown {
                // Resetting invalidates every service, characteristic and in-flight write too.
                self.stopScan()
                self.resetConnection(cancelPeripheral: false)
                current.delegate = nil
                self.central = nil
                self.peripherals = [:]
                self.devices = []
                self.status = Self.stateDescription(state)
            }
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let managerReference = MainQueueCBReference(value: central)
        let id = peripheral.identifier
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Aparelho sem nome"
        let rssi = RSSI.intValue
        let reference = MainQueueCBReference(value: peripheral)
        guard ["divoom", "ditoo", "timebox", "pixoo", "tivoo", "backpack"].contains(where: { name.localizedCaseInsensitiveContains($0) }) else { return }
        Task { @MainActor [weak self] in
            guard let self, let current = self.central, ObjectIdentifier(current) == ObjectIdentifier(managerReference.value), self.isScanning else { return }
            self.peripherals[id] = reference.value
            let item = MobileDivoomDevice(id: id, name: name, rssi: rssi)
            if let index = self.devices.firstIndex(where: { $0.id == id }) { self.devices[index] = item } else { self.devices.append(item) }
            self.devices.sort { $0.rssi > $1.rssi }
            if self.selectedDeviceID == nil { self.selectedDeviceID = id }
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        let managerReference = MainQueueCBReference(value: central)
        Task { @MainActor [weak self] in
            guard let self, let current = self.central, ObjectIdentifier(current) == ObjectIdentifier(managerReference.value) else { return }
            if self.sessionGate.cancellingDeviceID == id {
                if let retiring = self.peripherals[id] { current.cancelPeripheralConnection(retiring) }
                return
            }
            self.connected(id)
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        let managerReference = MainQueueCBReference(value: central)
        let message = error?.localizedDescription ?? "Conexão recusada."
        Task { @MainActor [weak self] in self?.terminalConnectionEvent(deviceID: id, message: message, managerID: ObjectIdentifier(managerReference.value)) }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        let managerReference = MainQueueCBReference(value: central)
        let message = error?.localizedDescription ?? "Conexão encerrada."
        Task { @MainActor [weak self] in self?.terminalConnectionEvent(deviceID: id, message: message, managerID: ObjectIdentifier(managerReference.value)) }
    }
}

private enum MobilePeripheralEvent: Sendable {
    case services(String?)
    case characteristics(String, String?)
    case value(String, Data?, String?)
    case wrote(String, String?)
    case ready
    case notification(String, Bool, String?)
}

/// One immutable proxy per connection attempt. Framework callbacks copy Sendable values
/// before hopping to MainActor; the epoch remains the one from this proxy's creation.
private final class EpochPeripheralDelegate: NSObject, CBPeripheralDelegate, @unchecked Sendable {
    private let epoch: UUID
    private let receive: @Sendable (UUID, UUID, MobilePeripheralEvent) -> Void
    init(epoch: UUID, receive: @escaping @Sendable (UUID, UUID, MobilePeripheralEvent) -> Void) {
        self.epoch = epoch
        self.receive = receive
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        receive(epoch, peripheral.identifier, .services(error?.localizedDescription))
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        receive(epoch, peripheral.identifier, .characteristics(service.uuid.uuidString, error?.localizedDescription))
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        receive(epoch, peripheral.identifier, .value(characteristic.uuid.uuidString, characteristic.value.map { Data($0) }, error?.localizedDescription))
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        receive(epoch, peripheral.identifier, .wrote(characteristic.uuid.uuidString, error?.localizedDescription))
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { receive(epoch, peripheral.identifier, .ready) }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        receive(epoch, peripheral.identifier, .notification(characteristic.uuid.uuidString, characteristic.isNotifying, error?.localizedDescription))
    }
}
