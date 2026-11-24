import Foundation
import Observation
import ObjectiveC
@preconcurrency import IOBluetooth

// The channel retains its pending buffer even if the controller disconnects before completion.
// An accepted write is buffered by IOBluetooth; association additionally keeps caller storage
// alive through the channel lifetime, avoiding a dangling pointer during cancellation.
nonisolated(unsafe) private var writeBufferAssociationKey: UInt8 = 0

private struct PendingRFCOMMWrite {
    let token: Int
    let channelID: ObjectIdentifier
    let buffer: NSMutableData
    let continuation: CheckedContinuation<IOReturn, Never>
}

struct PairedDivoomDevice: Identifiable, Equatable, Sendable {
    let address: String
    let name: String
    var id: String { address }
}

struct BluetoothLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date = Date()
    let direction: String
    let message: String
}

/// Owns one Classic Bluetooth connection, optionally reconnecting a remembered successful target.
/// A successful write or ACK never establishes what appeared on the display.
@MainActor
@Observable
final class BluetoothController: NSObject {
    private(set) var devices: [PairedDivoomDevice] = []
    var selectedAddress = ""
    var channel: UInt8 = 1
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var status = "Desconectado"
    private(set) var logs: [BluetoothLogEntry] = []
    private(set) var lastAcknowledgedCommand: UInt8?
    var sessionIdentifier: UUID { generation }

    var automaticConnectionEnabled = true {
        didSet {
            persistAutomaticPreferences()
            if automaticConnectionEnabled {
                backoff.reset()
                startAutomaticConnection()
            } else {
                automaticWanted = false
                cancelRetry()
                if connectionOrigin == .automatic && !isConnected {
                    cleanupConnection()
                    status = "Reconexão automática desativada"
                }
            }
        }
    }
    private(set) var rememberedDevice: RememberedRFCOMMDevice?
    var rememberedDeviceName: String? { rememberedDevice?.name }

    private enum ConnectionOrigin { case manual, automatic }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var automaticWanted = false
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryEpoch = UUID()
    @ObservationIgnored private var backoff = RFCOMMReconnectBackoff()
    @ObservationIgnored private var connectionOrigin: ConnectionOrigin?
    @ObservationIgnored private var attemptTarget: RememberedRFCOMMDevice?
    @ObservationIgnored private var channelDelegate: EpochRFCOMMDelegate?
    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var rfcomm: IOBluetoothRFCOMMChannel?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var pendingWrite: PendingRFCOMMWrite?
    @ObservationIgnored private var nextWriteToken = 1
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var parser = DivoomFrameParser()
    @ObservationIgnored private var acknowledgedCommands: Set<UInt8> = []

    init(defaults: UserDefaults = .standard, loadPairedDevices: Bool = true) {
        self.defaults = defaults
        let preferences = RFCOMMConnectionPreferences.load(from: defaults)
        automaticConnectionEnabled = preferences.enabled
        rememberedDevice = preferences.device
        selectedAddress = defaults.string(forKey: "divoom.address") ?? ""
        super.init()
        // Constructing the model never opens a connection. Tests can skip even the paired-device read.
        if loadPairedDevices { refreshDevices() }
    }

    isolated deinit {
        retryTask?.cancel()
        connectTask?.cancel()
        sendTask?.cancel()
        writeTask?.cancel()
        pendingWrite?.continuation.resume(returning: kIOReturnAborted)
        if let rfcomm {
            _ = rfcomm.setDelegate(nil)
            _ = rfcomm.close()
        }
    }

    func refreshDevices() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        devices = paired.compactMap { item in
            guard let rawAddress = item.addressString,
                  let address = Self.normalizedAddress(rawAddress) else { return nil }
            let name = item.name ?? address
            guard name.localizedCaseInsensitiveContains("divoom") ||
                    name.localizedCaseInsensitiveContains("ditoo") ||
                    name.localizedCaseInsensitiveContains("timebox") ||
                    name.localizedCaseInsensitiveContains("pixoo") ||
                    address == Self.normalizedAddress(selectedAddress) else { return nil }
            return PairedDivoomDevice(address: address, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Authorized lifecycle entry point; only the last successfully opened RFCOMM target qualifies.
    /// Reconnection never resends time, image, brightness, alarm or other application payloads.
    func startAutomaticConnection() {
        isSuspended = false
        guard automaticConnectionEnabled, rememberedDevice != nil else { return }
        if isBusy && connectionOrigin == .manual { return }
        automaticWanted = true
        guard !isConnected, !isBusy, retryTask == nil else { return }
        attemptAutomaticConnection()
    }

    func prepareForSleep() {
        isSuspended = true
        automaticWanted = false
        cancelRetry()
        cleanupConnection()
        status = "Conexão pausada enquanto o Mac dorme"
    }

    func forgetDevice() {
        automaticConnectionEnabled = false
        automaticWanted = false
        cancelRetry()
        rememberedDevice = nil
        persistAutomaticPreferences()
        cleanupConnection()
        selectedAddress = ""
        defaults.removeObject(forKey: "divoom.address")
        status = "Aparelho esquecido. Selecione e conecte novamente para salvá-lo."
    }

    private func persistAutomaticPreferences() {
        RFCOMMConnectionPreferences(enabled: automaticConnectionEnabled, device: rememberedDevice).save(to: defaults)
    }

    private func cancelRetry() {
        retryEpoch = UUID()
        retryTask?.cancel()
        retryTask = nil
    }

    private func attemptAutomaticConnection() {
        guard automaticWanted, automaticConnectionEnabled, !isSuspended, !isConnected,
              !isBusy, let target = rememberedDevice?.validated else { return }
        guard let host = IOBluetoothHostController.default(), host.powerState == kBluetoothHCIPowerStateON else {
            status = "Aguardando o Bluetooth do Mac ficar disponível"
            scheduleRetry()
            return
        }
        guard let candidate = IOBluetoothDevice(addressString: target.address), candidate.isPaired() else {
            status = "O aparelho salvo precisa estar emparelhado com este Mac"
            scheduleRetry()
            return
        }
        openConnection(to: candidate, target: target, origin: .automatic)
    }

    private func scheduleRetry() {
        guard automaticWanted, automaticConnectionEnabled, !isSuspended, !isConnected,
              !isBusy, rememberedDevice?.validated != nil, retryTask == nil else { return }
        let delay = backoff.nextDelay()
        let epoch = retryEpoch
        appendLog("AUTO", "Nova tentativa de conexão em \(Int(delay)) s; nenhum comando será repetido.")
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.retryEpoch == epoch, !Task.isCancelled else { return }
            self.retryTask = nil
            self.attemptAutomaticConnection()
        }
    }

    func connect() {
        guard !isBusy, !isConnected else { return }
        guard let address = Self.normalizedAddress(selectedAddress), (1...30).contains(channel) else {
            status = "Endereço Bluetooth inválido ou canal fora de 1…30"
            appendLog("ERRO", status)
            return
        }
        isSuspended = false
        cancelRetry()
        // A failed new selection is never promoted to an automatic target.
        automaticWanted = automaticConnectionEnabled && rememberedDevice?.address == address && rememberedDevice?.channel == channel
        selectedAddress = address
        defaults.set(address, forKey: "divoom.address") // selection only; not proof of a successful connection
        guard let target = IOBluetoothDevice(addressString: address) else {
            status = "Não foi possível localizar o aparelho"
            appendLog("ERRO", status)
            scheduleRetry()
            return
        }
        let configuration = RememberedRFCOMMDevice(address: address, name: target.name ?? "Ditoo", channel: channel)
        openConnection(to: target, target: configuration, origin: .manual)
    }

    private func openConnection(to targetDevice: IOBluetoothDevice, target: RememberedRFCOMMDevice, origin: ConnectionOrigin) {
        // Internal cleanup must not invoke the user's Disconnect opt-out.
        cleanupConnection()
        device = targetDevice
        attemptTarget = target
        selectedAddress = target.address
        channel = target.channel
        connectionOrigin = origin
        isBusy = true
        status = origin == .automatic ? "Reconectando ao aparelho salvo…" : "Conectando…"
        appendLog(origin == .automatic ? "AUTO" : "INFO", "Abrindo RFCOMM, canal \(target.channel); sem comandos automáticos")
        let attempt = generation
        let proxy = EpochRFCOMMDelegate(epoch: attempt) { [weak self] epoch, event in
            Task { @MainActor [weak self] in self?.receiveChannelEvent(event, epoch: epoch) }
        }
        channelDelegate = proxy
        var opened: IOBluetoothRFCOMMChannel?
        let result = targetDevice.openRFCOMMChannelAsync(&opened, withChannelID: target.channel, delegate: proxy)
        rfcomm = opened
        guard result == kIOReturnSuccess, opened != nil else {
            status = "Falha ao abrir RFCOMM: \(Self.errorCode(result)). Se o áudio estiver em uso, desconecte-o nos ajustes Bluetooth."
            appendLog("ERRO", status)
            cleanupConnection()
            scheduleRetry()
            return
        }
        connectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == attempt, !self.isConnected else { return }
            self.status = "Conexão expirou após 15 segundos"
            self.appendLog("ERRO", self.status)
            self.cleanupConnection()
            self.scheduleRetry()
        }
    }

    func disconnect() {
        automaticConnectionEnabled = false
        automaticWanted = false
        cancelRetry()
        cleanupConnection()
        status = "Desconectado; reconexão automática desativada"
    }

    func send(_ payloads: [Data], label: String) {
        guard isConnected, let connection = rfcomm, connection.isOpen() else {
            status = "Conecte o aparelho antes de enviar"
            appendLog("ERRO", status)
            return
        }
        guard !isBusy else { return }
        guard !payloads.isEmpty, payloads.count <= 256,
              payloads.allSatisfy({ !$0.isEmpty && $0.count <= 60_000 }) else {
            status = "Envio recusado: lista vazia ou pacote fora do limite"
            appendLog("ERRO", status)
            return
        }
        let frames = payloads.map { DivoomProtocol.frame($0) }
        let commands = Set(payloads.compactMap(\.first))
        acknowledgedCommands.removeAll()
        lastAcknowledgedCommand = nil
        let attempt = generation
        isBusy = true
        status = "Enviando \(label)…"
        appendLog("INFO", "\(label): \(frames.count) pacote(s); sem repetição automática")
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == attempt {
                    self.isBusy = false
                    self.sendTask = nil
                }
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            for frame in frames {
                guard !Task.isCancelled, self.generation == attempt else { return }
                guard let current = self.rfcomm, current.isOpen() else {
                    self.status = "Envio interrompido: canal fechado"
                    self.appendLog("ERRO", self.status)
                    self.cleanupConnection()
                    self.scheduleRetry()
                    return
                }
                let mtu = max(1, min(200, Int(current.getMTU())))
                var offset = 0
                while offset < frame.count {
                    guard !Task.isCancelled, self.generation == attempt else { return }
                    guard current.isOpen() else {
                        self.status = "Envio interrompido: canal fechado"
                        self.appendLog("ERRO", self.status)
                        self.cleanupConnection()
                        self.scheduleRetry()
                        return
                    }
                    guard ContinuousClock.now < deadline else {
                        self.status = "Envio expirou após 60 segundos; sem nova tentativa"
                        self.appendLog("ERRO", self.status)
                        self.cleanupConnection()
                        self.scheduleRetry()
                        return
                    }
                    let count = min(mtu, frame.count - offset)
                    let bytes = Data(frame[offset..<(offset + count)])
                    let result = await self.write(bytes, to: current)
                    guard self.generation == attempt, !Task.isCancelled else { return }
                    guard result == kIOReturnSuccess else {
                        self.status = "Falha no envio: \(Self.errorCode(result)); sem nova tentativa"
                        self.appendLog("ERRO", self.status)
                        self.cleanupConnection()
                        self.scheduleRetry()
                        return
                    }
                    offset += count
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
                self.appendLog("TX", Self.hex(frame))
                do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            }
            // Let the run loop deliver replies. Some devices do not ACK every command.
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard self.generation == attempt, !Task.isCancelled else { return }
            let observed = self.acknowledgedCommands.intersection(commands)
            self.isBusy = false
            if observed.isEmpty {
                self.status = "\(label): enviado; sem ACK correspondente. Confira o aparelho."
            } else {
                self.status = "\(label): enviado; resposta observada para \(observed.count) comando(s) distinto(s), sem confirmação por pacote. Confira o aparelho."
            }
            self.appendLog("INFO", self.status)
            self.sendTask = nil
        }
    }

    func exportLog() -> String {
        let formatter = ISO8601DateFormatter()
        return logs.map { "\(formatter.string(from: $0.date)) [\($0.direction)] \($0.message)" }
            .joined(separator: "\n")
    }

    private func cleanupConnection() {
        generation = UUID()
        connectTask?.cancel()
        connectTask = nil
        sendTask?.cancel()
        sendTask = nil
        writeTask?.cancel()
        writeTask = nil
        if let pendingWrite {
            self.pendingWrite = nil
            pendingWrite.continuation.resume(returning: kIOReturnAborted)
        }
        if let rfcomm {
            _ = rfcomm.setDelegate(nil)
            _ = rfcomm.close()
        }
        rfcomm = nil
        channelDelegate = nil
        device = nil
        attemptTarget = nil
        connectionOrigin = nil
        isConnected = false
        isBusy = false
        parser.reset()
        acknowledgedCommands.removeAll()
        lastAcknowledgedCommand = nil
    }

    private func write(_ bytes: Data, to connection: IOBluetoothRFCOMMChannel) async -> IOReturn {
        guard pendingWrite == nil, connection.isOpen(), !Task.isCancelled else { return kIOReturnAborted }
        let token = nextWriteToken
        nextWriteToken += 1
        let identity = ObjectIdentifier(connection)
        let buffer = NSMutableData(data: bytes)
        return await withCheckedContinuation { continuation in
            pendingWrite = PendingRFCOMMWrite(token: token, channelID: identity, buffer: buffer, continuation: continuation)
            objc_setAssociatedObject(connection, &writeBufferAssociationKey, buffer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let result = connection.writeAsync(buffer.mutableBytes, length: UInt16(bytes.count), refcon: UnsafeMutableRawPointer(bitPattern: token))
            guard result == kIOReturnSuccess else {
                completeWrite(token: token, channelID: identity, result: result)
                return
            }
            writeTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.pendingWrite?.token == token else { return }
                self.status = "Escrita Bluetooth expirou após 5 segundos; sem nova tentativa"
                self.appendLog("ERRO", self.status)
                // close() cancels channel activity; caller storage stays associated with it.
                self.cleanupConnection()
                self.scheduleRetry()
            }
        }
    }

    private func completeWrite(token: Int, channelID: ObjectIdentifier, result: IOReturn) {
        guard let pending = pendingWrite, pending.token == token, pending.channelID == channelID else { return }
        pendingWrite = nil
        writeTask?.cancel()
        writeTask = nil
        if let connection = rfcomm, ObjectIdentifier(connection) == channelID {
            objc_setAssociatedObject(connection, &writeBufferAssociationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        pending.continuation.resume(returning: result)
    }

    private func appendLog(_ direction: String, _ message: String) {
        logs.append(BluetoothLogEntry(direction: direction, message: message))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        // Retain complete packets while bounding exported text to approximately 2 MB.
        while logs.count > 1, logs.reduce(0, { $0 + $1.message.utf8.count }) > 2_000_000 { logs.removeFirst() }
    }

    private func receive(_ data: Data, from channelID: ObjectIdentifier) {
        guard let current = rfcomm, ObjectIdentifier(current) == channelID else { return }
        appendLog("RX", Self.hex(data))
        for payload in parser.append(data) {
            if let command = DivoomProtocol.acknowledgedCommand(in: payload) {
                lastAcknowledgedCommand = command
                acknowledgedCommands.insert(command)
                appendLog("ACK", String(format: "Resposta ao comando 0x%02X; dados %@", command, Self.hex(Data(payload.dropFirst(3)))))
            }
        }
    }

    private func receiveChannelEvent(_ event: RFCOMMChannelEvent, epoch: UUID) {
        guard let current = rfcomm,
              RFCOMMCallbackScope(epoch: epoch, channelID: event.channelID)
                .isCurrent(epoch: generation, channelID: ObjectIdentifier(current)) else { return }
        switch event {
        case .opened(_, let error):
            connectTask?.cancel()
            connectTask = nil
            guard error == kIOReturnSuccess, current.isOpen() else {
                status = "Conexão falhou: \(Self.errorCode(error))"
                appendLog("ERRO", status)
                cleanupConnection()
                scheduleRetry()
                return
            }
            isConnected = true
            isBusy = false
            if let target = attemptTarget?.validated {
                rememberedDevice = target
                persistAutomaticPreferences()
                automaticWanted = automaticConnectionEnabled
            }
            backoff.reset()
            cancelRetry()
            status = "Conectado por Bluetooth; aguardando ação"
            appendLog("INFO", status)
        case .closed:
            cleanupConnection()
            status = "Conexão encerrada pelo aparelho"
            appendLog("INFO", status)
            scheduleRetry()
        case .data(_, let data): receive(data, from: event.channelID)
        case .write(_, let token, let status, let bytesWritten):
            guard let pending = pendingWrite, pending.token == token, pending.channelID == event.channelID else { return }
            let result = status == kIOReturnSuccess && bytesWritten != nil && bytesWritten != pending.buffer.length
                ? kIOReturnUnderrun : status
            completeWrite(token: token, channelID: event.channelID, result: result)
        }
    }

    private static func normalizedAddress(_ value: String) -> String? {
        RFCOMMConnectionPreferences.normalizedAddress(value)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func errorCode(_ error: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: error))
    }
}


private enum RFCOMMChannelEvent: Sendable {
    case opened(ObjectIdentifier, IOReturn)
    case closed(ObjectIdentifier)
    case data(ObjectIdentifier, Data)
    case write(ObjectIdentifier, Int, IOReturn, Int?)
    var channelID: ObjectIdentifier {
        switch self {
        case .opened(let id, _), .closed(let id), .data(let id, _), .write(let id, _, _, _): id
        }
    }
}

/// One immutable proxy per RFCOMM open. Callback pointers/buffers are copied before
/// the MainActor hop, and an old epoch never mutates a newly opened channel.
private final class EpochRFCOMMDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    private let epoch: UUID
    private let receive: @Sendable (UUID, RFCOMMChannelEvent) -> Void
    init(epoch: UUID, receive: @escaping @Sendable (UUID, RFCOMMChannelEvent) -> Void) {
        self.epoch = epoch
        self.receive = receive
    }
    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard let channel else { return }
        receive(epoch, .opened(ObjectIdentifier(channel), error))
    }
    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        guard let channel else { return }
        receive(epoch, .closed(ObjectIdentifier(channel)))
    }
    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard let channel, let pointer, length > 0 else { return }
        receive(epoch, .data(ObjectIdentifier(channel), Data(bytes: pointer, count: length)))
    }
    func rfcommChannelWriteComplete(_ channel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        guard let channel, let refcon else { return }
        receive(epoch, .write(ObjectIdentifier(channel), Int(bitPattern: refcon), error, nil))
    }
    func rfcommChannelWriteComplete(_ channel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn, bytesWritten: Int) {
        guard let channel, let refcon else { return }
        receive(epoch, .write(ObjectIdentifier(channel), Int(bitPattern: refcon), error, bytesWritten))
    }
}
