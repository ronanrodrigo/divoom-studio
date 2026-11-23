import SwiftUI
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    let bluetooth = BluetoothController()
    let dashboard = DashboardModel()
    var project: PixelProject
    var selectedFrameID: UUID
    var drawingColor = Color.cyan
    var erasing = false
    var isPlaying = false
    var message = "Pronto para criar. Nenhum comando é enviado automaticamente."
    var library: [LibraryEntry] = []
    var brightness = 50.0
    var displayOn = true
    var clockStyle = 0
    var twentyFourHour = true
    var clockColor = Color.cyan
    var mode = 0
    var hasConfiguredAlarm = UserDefaults.standard.object(forKey: "alarm.configuredTime") != nil
    var alarmTime = (UserDefaults.standard.object(forKey: "alarm.configuredTime") as? Date) ?? Date() {
        didSet { hasConfiguredAlarm = true; UserDefaults.standard.set(alarmTime, forKey: "alarm.configuredTime") }
    }
    var alarmEnabled = UserDefaults.standard.bool(forKey: "alarm.configuredEnabled") {
        didSet { UserDefaults.standard.set(alarmEnabled, forKey: "alarm.configuredEnabled") }
    }
    var alarmLabel = "Despertar"
    private var playbackTask: Task<Void, Never>?

    init() {
        let initial = PixelProject()
        project = initial
        selectedFrameID = initial.frames[0].id
        refreshLibrary()
    }

    var currentFrame: PixelFrame { project.frames.first(where: { $0.id == selectedFrameID }) ?? project.frames[0] }
    var frameNumber: Int { (project.frames.firstIndex(where: { $0.id == selectedFrameID }) ?? 0) + 1 }
    var canSend: Bool { bluetooth.isConnected && !bluetooth.isBusy }

    func paint(x: Int, y: Int) {
        guard !isPlaying, (0..<16).contains(x), (0..<16).contains(y), let index = project.frames.firstIndex(where: { $0.id == selectedFrameID }) else { return }
        let color = erasing ? (UInt8(0), UInt8(0), UInt8(0)) : Self.rgb(drawingColor)
        let offset = (y * 16 + x) * 3
        project.frames[index].rgb.replaceSubrange(offset..<(offset + 3), with: [color.0, color.1, color.2])
    }
    func clearFrame() { guard let index = project.frames.firstIndex(where: { $0.id == selectedFrameID }) else { return }; project.frames[index].rgb = Array(repeating: 0, count: 768) }
    func addFrame(duplicate: Bool) {
        guard project.frames.count < 60 else { message = "Limite de 60 quadros por projeto."; return }
        var frame = duplicate ? currentFrame : PixelFrame(); frame.id = UUID()
        project.frames.append(frame); selectedFrameID = frame.id
    }
    func deleteFrame() { guard project.frames.count > 1 else { return }; project.frames.removeAll { $0.id == selectedFrameID }; selectedFrameID = project.frames[0].id }
    func togglePlayback() {
        isPlaying.toggle(); playbackTask?.cancel()
        guard isPlaying else { return }
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await Task.sleep(for: .milliseconds(self.project.durationMilliseconds)) } catch { return }
                let index = self.project.frames.firstIndex(where: { $0.id == self.selectedFrameID }) ?? 0
                self.selectedFrameID = self.project.frames[(index + 1) % self.project.frames.count].id
            }
        }
    }
    func stopPlayback() { isPlaying = false; playbackTask?.cancel(); playbackTask = nil }
    func sendFrame() { do { bluetooth.send(try DivoomProtocol.image(rgb: currentFrame.rgb), label: "Imagem 16 × 16") } catch { message = error.localizedDescription } }
    func sendAnimation() { do { bluetooth.send(try DivoomProtocol.animation(frames: project.frames.map(\.rgb), durationMilliseconds: project.durationMilliseconds), label: "Animação") } catch { message = error.localizedDescription } }
    func applyClock() { bluetooth.send([DivoomProtocol.timeFormat(twentyFourHour: twentyFourHour), DivoomProtocol.clock(style: UInt8(clockStyle), twentyFourHour: twentyFourHour, color: Self.rgb(clockColor))], label: "Relógio") }
    func applyBrightness() { bluetooth.send([DivoomProtocol.brightness(Int(brightness))], label: "Brilho") }
    func applyScreen() { bluetooth.send([DivoomProtocol.screen(displayOn)], label: "Tela") }
    func syncTime() { bluetooth.send([DivoomProtocol.syncTime(Date())], label: "Sincronizar horário") }
    func applyMode() { bluetooth.send([DivoomProtocol.channel(UInt8(mode))], label: "Modo de tela") }

    static func rgb(_ color: Color) -> (UInt8, UInt8, UInt8) {
        let c = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        return (UInt8(max(0, min(255, c.redComponent * 255))), UInt8(max(0, min(255, c.greenComponent * 255))), UInt8(max(0, min(255, c.blueComponent * 255))))
    }
    func importMedia() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let imported = try PixelMedia.importMedia(from: url); let frames = imported.frames; guard !frames.isEmpty else { throw CocoaError(.fileReadCorruptFile) }; stopPlayback(); project.frames = frames; project.durationMilliseconds = imported.durationMilliseconds; project.name = url.deletingPathExtension().lastPathComponent; selectedFrameID = frames[0].id; message = imported.hasVariableTiming ? "Mídia importada em 16 × 16. Tempos variáveis normalizados para \(imported.durationMilliseconds) ms por quadro." : "Mídia importada e ajustada para 16 × 16." } catch { message = error.localizedDescription }
    }
    func exportMedia(animated: Bool) {
        let panel = NSSavePanel(); panel.allowedContentTypes = animated ? [.gif] : [.png]; panel.nameFieldStringValue = project.name + (animated ? ".gif" : ".png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { var output = project; if !animated { output.frames = [currentFrame] }; try PixelMedia.export(output, to: url, animated: animated); message = "Arquivo exportado." } catch { message = error.localizedDescription }
    }
    func saveProject() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = project.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(project).write(to: url, options: .atomic); message = "Projeto salvo." } catch { message = error.localizedDescription }
    }
    func openProject(url: URL? = nil) {
        var target = url
        if target == nil { let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; guard panel.runModal() == .OK else { return }; target = panel.url }
        guard let target else { return }
        do { let loaded = try PixelProject.load(from: target); stopPlayback(); project = loaded; selectedFrameID = loaded.frames[0].id; message = "Projeto aberto." } catch { message = error.localizedDescription }
    }
    private var libraryDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "DivoomStudio/Library", directoryHint: .isDirectory) }
    func refreshLibrary() { library = ((try? FileManager.default.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { LibraryEntry(id: $0, name: $0.deletingPathExtension().lastPathComponent) } }
    func addToLibrary() { do { try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true); let safe = project.name.replacingOccurrences(of: "/", with: "-"); let url = libraryDirectory.appending(path: "\(safe)-\(UUID().uuidString.prefix(6)).json"); try JSONEncoder().encode(project).write(to: url, options: .atomic); refreshLibrary(); message = "Projeto adicionado à biblioteca local." } catch { message = error.localizedDescription } }
    func exportLogs() { let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "divoom-diagnostico.txt"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try bluetooth.exportLog().write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription } }
}
