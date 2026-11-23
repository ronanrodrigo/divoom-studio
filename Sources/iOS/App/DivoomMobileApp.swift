import SwiftUI

@main
struct DivoomMobileApp: App {
    @State private var model = MobileAppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MobileRootView(model: model)
                .tint(.cyan)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: break
                    case .inactive: model.becameInactive()
                    case .background: model.enteredBackground()
                    @unknown default: model.enteredBackground()
                    }
                }
        }
    }
}

struct MobileRootView: View {
    let model: MobileAppModel
    var body: some View {
        if #available(iOS 18, *) {
            TabView {
                Tab("Painel", systemImage: "square.grid.2x2") {
                    NavigationStack { MobileDashboardView(model: model) }
                }
                Tab("Editor", systemImage: "square.grid.3x3") {
                    NavigationStack { MobileEditorView(model: model) }
                }
                Tab("Aparelho", systemImage: "hifispeaker") {
                    NavigationStack { MobileDeviceView(model: model) }
                }
            }
        } else {
            MobileLegacyTabs(model: model)
        }
    }
}

/// Compatibility branch for iOS17, where the Tab content API is unavailable.
private struct MobileLegacyTabs: View {
    let model: MobileAppModel
    var body: some View {
        TabView {
            NavigationStack { MobileDashboardView(model: model) }.tabItem { Label("Painel", systemImage: "square.grid.2x2") }
            NavigationStack { MobileEditorView(model: model) }.tabItem { Label("Editor", systemImage: "square.grid.3x3") }
            NavigationStack { MobileDeviceView(model: model) }.tabItem { Label("Aparelho", systemImage: "hifispeaker") }
        }
    }
}
