import SwiftUI

struct PixelEditorView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    TextField("Nome do projeto", text: $model.project.name).font(.title2.weight(.semibold)).textFieldStyle(.plain)
                    Spacer()
                    Button("Importar…", action: model.importMedia)
                    Menu("Exportar") {
                        Button("Imagem PNG…", action: { model.exportMedia(animated: false) })
                        Button("Animação GIF…", action: { model.exportMedia(animated: true) })
                        Divider()
                        Button("Projeto JSON…", action: model.saveProject)
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    PixelCanvas(rgb: model.currentFrame.rgb, paint: model.paint)
                        .frame(width: 400, height: 400)
                        .disabled(model.isPlaying)
                    EditorTools(model: model)
                }
                FrameStrip(model: model)
                VerificationNote()
            }.padding(24)
        }
    }
}

struct PixelCanvas: View {
    let rgb: [UInt8]
    var paint: (Int, Int) -> Void
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 16
            for y in 0..<16 {
                for x in 0..<16 {
                    let index = (y * 16 + x) * 3
                    guard index + 2 < rgb.count else { continue }
                    let color = Color(red: Double(rgb[index]) / 255, green: Double(rgb[index + 1]) / 255, blue: Double(rgb[index + 2]) / 255)
                    let rect = CGRect(x: Double(x) * cell, y: Double(y) * cell, width: cell - 1, height: cell - 1)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .background(.gray.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        paint(Int(value.location.x / (geometry.size.width / 16)), Int(value.location.y / (geometry.size.height / 16)))
                    }
                )
            }
        }
        .accessibilityLabel("Tela de desenho, 16 por 16 pixels")
        .accessibilityHint("Arraste para pintar. Use os campos de coordenadas para editar por teclado.")
    }
}

struct EditorTools: View {
    @Bindable var model: AppModel
    @State private var x = 0
    @State private var y = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ferramentas").font(.headline)
            ColorPicker("Cor", selection: $model.drawingColor, supportsOpacity: false)
            Toggle("Borracha", isOn: $model.erasing)
            Button("Limpar quadro", action: model.clearFrame).disabled(model.isPlaying)
            Divider()
            Text("Editar com o teclado").font(.subheadline.weight(.medium))
            Stepper("Coluna: \(x + 1)", value: $x, in: 0...15)
            Stepper("Linha: \(y + 1)", value: $y, in: 0...15)
            Button("Pintar pixel", action: { model.paint(x: x, y: y) })
            Divider()
            Button("Enviar quadro", action: model.sendFrame).buttonStyle(.borderedProminent).disabled(!model.canSend)
            Button("Enviar animação", action: model.sendAnimation).disabled(!model.canSend || model.project.frames.count < 2)
            Button("Guardar na biblioteca", action: model.addToLibrary)
        }.frame(minWidth: 220, maxWidth: 330, alignment: .leading)
    }
}

struct FrameStrip: View {
    @Bindable var model: AppModel
    var body: some View {
        StudioCard(title: "Quadros", symbol: "film.stack") {
            HStack {
                Button(model.isPlaying ? "Pausar prévia" : "Reproduzir prévia", systemImage: model.isPlaying ? "pause.fill" : "play.fill", action: model.togglePlayback)
                Text("Quadro \(model.frameNumber) de \(model.project.frames.count)").foregroundStyle(.secondary)
                Spacer()
                Stepper("\(model.project.durationMilliseconds) ms", value: $model.project.durationMilliseconds, in: 50...5000, step: 50)
                    .fixedSize()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.project.frames) { frame in
                        Button { model.selectedFrameID = frame.id } label: {
                            FrameThumbnail(rgb: frame.rgb)
                                .frame(width: 64, height: 64)
                                .padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selectedFrameID == frame.id ? Color.cyan : Color.secondary.opacity(0.2), lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("Selecionar quadro")
                    }
                }.padding(3)
            }
            HStack {
                Button("Adicionar quadro", action: { model.addFrame(duplicate: false) })
                Button("Duplicar", action: { model.addFrame(duplicate: true) })
                Button("Excluir quadro", action: model.deleteFrame).disabled(model.project.frames.count == 1)
            }.disabled(model.isPlaying)
        }
    }
}

struct FrameThumbnail: View {
    let rgb: [UInt8]
    var body: some View {
        Group {
            if let image = PixelMedia.image(rgb) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
            } else { Color.black }
        }.background(.black).clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
