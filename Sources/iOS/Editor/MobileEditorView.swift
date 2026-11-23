import SwiftUI
import UniformTypeIdentifiers

enum MobileExportKind: String, CaseIterable, Identifiable {
    case png, gif, project
    var id: String { rawValue }
    var contentType: UTType { switch self { case .png: .png; case .gif: .gif; case .project: .json } }
}

struct MobileExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png, .gif, .json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct MobileEditorView: View {
    @Bindable var model: MobileAppModel
    @State private var importing = false
    @State private var exporting = false
    @State private var document: MobileExportDocument?
    @State private var exportKind: MobileExportKind = .png
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Nome do projeto", text: $model.project.name).font(.title2.bold()).textFieldStyle(.roundedBorder)
                MobileDrawingCanvas(rgb: model.currentFrame.rgb, paint: model.paint).frame(maxWidth: 420).frame(maxWidth: .infinity).disabled(model.isPlaying)
                MobileDrawingTools(model: model)
                MobileFrameStrip(model: model)
                MobileCard(title: "Enviar ao aparelho") {
                    Button("Enviar quadro atual", action: model.sendFrame).buttonStyle(.borderedProminent).disabled(!model.canSend)
                    Button("Enviar animação", action: model.sendAnimation).disabled(!model.canSend || model.project.frames.count < 2)
                    Text("Upload BLE experimental com confirmação por pacote. Confira o resultado no aparelho.").font(.caption).foregroundStyle(.secondary)
                    Text("Os arquivos continuam editáveis sem um Ditoo conectado.").font(.caption).foregroundStyle(.secondary)
                }
                Text(model.message).font(.callout).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Editor")
        .toolbar {
            Menu {
                Button("Importar imagem, GIF ou projeto", action: { importing = true })
                Button("Exportar PNG", action: { prepareExport(.png) })
                Button("Exportar GIF", action: { prepareExport(.gif) })
                Button("Exportar projeto JSON", action: { prepareExport(.project) })
                Button("Guardar na biblioteca", action: model.saveToLibrary)
            } label: { Label("Arquivos", systemImage: "square.and.arrow.up") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .gif, .json], allowsMultipleSelection: false) { result in
            switch result { case .success(let urls): if let url = urls.first { model.importFile(url) }; case .failure(let error): model.message = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportKind.contentType, defaultFilename: model.project.name) { result in
            switch result { case .success: model.message = "Arquivo exportado."; case .failure(let error): model.message = error.localizedDescription }
        }
    }
    private func prepareExport(_ kind: MobileExportKind) {
        do { document = MobileExportDocument(data: try model.exportData(kind: kind)); exportKind = kind; exporting = true } catch { model.message = error.localizedDescription }
    }
}

struct MobileDrawingCanvas: View {
    let rgb: [UInt8]
    var paint: (Int, Int) -> Void
    var body: some View {
        MobilePixelPreview(rgb: rgb)
            .accessibilityIdentifier("mobile.pixelCanvas")
            .overlay {
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        paint(Int(value.location.x / (geometry.size.width / 16)), Int(value.location.y / (geometry.size.height / 16)))
                    })
                }
            }
            .accessibilityHint("Arraste para pintar. Para editar com VoiceOver, use os controles de coluna e linha abaixo.")
    }
}

struct MobileDrawingTools: View {
    @Bindable var model: MobileAppModel
    @State private var column = 0
    @State private var row = 0
    var body: some View {
        MobileCard(title: "Ferramentas") {
            ColorPicker("Cor do pixel", selection: $model.color, supportsOpacity: false)
            Toggle("Borracha", isOn: $model.erasing)
            Button("Limpar quadro", role: .destructive, action: model.clearFrame)
            DisclosureGroup("Editar um pixel por coordenadas") {
                Stepper("Coluna \(column + 1)", value: $column, in: 0...15)
                Stepper("Linha \(row + 1)", value: $row, in: 0...15)
                Button("Pintar pixel selecionado") { model.paint(x: column, y: row) }
            }
        }.disabled(model.isPlaying)
    }
}

struct MobileFrameStrip: View {
    @Bindable var model: MobileAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        MobileCard(title: "Animação") {
            Button(model.isPlaying ? "Pausar prévia" : "Reproduzir prévia", systemImage: model.isPlaying ? "pause.fill" : "play.fill", action: model.togglePlayback).accessibilityIdentifier("mobile.playback")
            Stepper("Duração: \(model.project.durationMilliseconds) ms", value: $model.project.durationMilliseconds, in: 50...5000, step: 50)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.project.frames) { frame in
                        Button { model.selectedFrameID = frame.id } label: {
                            MobilePixelPreview(rgb: frame.rgb).frame(width: 64, height: 64).padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedFrameID == frame.id ? Color.cyan : Color.secondary.opacity(0.2), lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("Quadro da animação").accessibilityAddTraits(model.selectedFrameID == frame.id ? .isSelected : [])
                    }
                }.padding(3)
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { frameButtons }
                } else {
                    HStack { frameButtons }
                }
            }.disabled(model.isPlaying)
            Text("\(model.project.frames.count) de 60 quadros")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("mobile.frameCount")
                .accessibilityValue("\(model.project.frames.count)")
        }
    }
    @ViewBuilder private var frameButtons: some View {
        Button("Adicionar", systemImage: "plus", action: { model.addFrame(duplicate: false) }).accessibilityIdentifier("mobile.addFrame")
        Button("Duplicar", systemImage: "square.on.square", action: { model.addFrame(duplicate: true) }).accessibilityIdentifier("mobile.duplicateFrame")
        Button("Excluir", systemImage: "trash", role: .destructive, action: model.deleteFrame).disabled(model.project.frames.count < 2).accessibilityIdentifier("mobile.deleteFrame")
    }
}
