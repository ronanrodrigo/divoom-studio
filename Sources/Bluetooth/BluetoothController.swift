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

/// Owns exactly one user-initiated Classic Bluetooth connection.
/// A successful write or ACK never establishes what appeared on the display.
@MainActor
@Observable
final class BluetoothController: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private(set) var devices: [PairedDivoomDevice] = []
    var selectedAddress: String = UserDefaults.standard.string(forKey: "divoom.address") ?? ""
    var channel: UInt8 = 1
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var status = "Desconectado"
    private(set) var logs: [BluetoothLogEntry] = []
    private(set) var lastAcknowledgedCommand: UInt8?

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

    override init() {
        super.init()
        // Reading paired devices does not initiate discovery, connection or transmission.
        refreshDevices()
    }

    isolated deinit {
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

    func connect() {
        guard !isBusy, !isConnected else { return }
        guard let address = Self.normalizedAddress(selectedAddress), (1...30).contains(channel) else {
            status = "Endereço Bluetooth inválido ou canal fora de 1…30"
            appendLog("ERRO", status)
            return
        }
        disconnect()
        selectedAddress = address
        UserDefaults.standard.set(address, forKey: "divoom.address")
        guard let target = IOBluetoothDevice(addressString: address) else {
            status = "Não foi possível localizar o aparelho"
            appendLog("ERRO", status)
            return
        }
        device = target
        isBusy = true
        status = "Conectando…"
        appendLog("INFO", "Abrindo RFCOMM \(address), canal \(channel)")
        let attempt = generation
        var opened: IOBluetoothRFCOMMChannel?
        let result = target.openRFCOMMChannelAsync(&opened, withChannelID: channel, delegate: self)
        rfcomm = opened
        guard result == kIOReturnSuccess, opened != nil else {
            status = "Falha ao abrir RFCOMM: \(Self.errorCode(result)). Se o áudio estiver em uso, desconecte-o nos ajustes Bluetooth."
            appendLog("ERRO", status)
            cleanupConnection()
            return
        }
        connectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == attempt, !self.isConnected else { return }
            self.status = "Conexão expirou após 15 segundos"
            self.appendLog("ERRO", self.status)
            self.cleanupConnection()
        }
    }

    func disconnect() {
        cleanupConnection()
        status = "Desconectado"
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
                        return
                    }
                    guard ContinuousClock.now < deadline else {
                        self.status = "Envio expirou após 60 segundos; sem nova tentativa"
                        self.appendLog("ERRO", self.status)
                        self.cleanupConnection()
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
        device = nil
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

    nonisolated func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        guard let rfcommChannel, let refcon else { return }
        let identity = ObjectIdentifier(rfcommChannel)
        let token = Int(bitPattern: refcon)
        Task { @MainActor [weak self] in
            self?.completeWrite(token: token, channelID: identity, result: error)
        }
    }

    nonisolated func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn, bytesWritten length: Int) {
        guard let rfcommChannel, let refcon else { return }
        let identity = ObjectIdentifier(rfcommChannel)
        let token = Int(bitPattern: refcon)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = error == kIOReturnSuccess && length != self.pendingWrite?.buffer.length ? kIOReturnUnderrun : error
            self.completeWrite(token: token, channelID: identity, result: result)
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let rfcommChannel, let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        let identity = ObjectIdentifier(rfcommChannel)
        Task { @MainActor [weak self] in self?.receive(data, from: identity) }
    }

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard let rfcommChannel else { return }
        let identity = ObjectIdentifier(rfcommChannel)
        Task { @MainActor [weak self] in
            guard let self, let current = self.rfcomm, ObjectIdentifier(current) == identity else { return }
            self.connectTask?.cancel()
            self.connectTask = nil
            guard error == kIOReturnSuccess else {
                self.status = "Conexão falhou: \(Self.errorCode(error))"
                self.appendLog("ERRO", self.status)
                self.cleanupConnection()
                return
            }
            self.isConnected = true
            self.isBusy = false
            self.status = "Conectado por Bluetooth; aguardando ação"
            self.appendLog("INFO", self.status)
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard let rfcommChannel else { return }
        let identity = ObjectIdentifier(rfcommChannel)
        Task { @MainActor [weak self] in
            guard let self, let current = self.rfcomm, ObjectIdentifier(current) == identity else { return }
            self.cleanupConnection()
            self.status = "Conexão encerrada pelo aparelho"
            self.appendLog("INFO", self.status)
        }
    }

    private static func normalizedAddress(_ value: String) -> String? {
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: ":").uppercased()
        let parts = compact.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else { return nil }
        return compact
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func errorCode(_ error: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: error))
    }
}
