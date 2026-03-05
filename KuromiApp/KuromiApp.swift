import SwiftUI

@main
struct KuromiApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

class AppState: ObservableObject {
    @Published var isSetupComplete: Bool = false
    @Published var currentScreen: AppScreen = .setup
    @Published var isSetupEditMode: Bool = false

    init() {
        isSetupComplete = AppSettings.load() != nil
        if isSetupComplete {
            currentScreen = .chat
        }
    }

    func openSetupEdit() {
        isSetupEditMode = true
        currentScreen = .setup
    }

    func closeSetupEdit() {
        isSetupEditMode = false
        currentScreen = .chat
    }
}

enum AppScreen: Equatable {
    case setup
    case chat
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .setup:
                SetupView(isEditMode: appState.isSetupEditMode)
            case .chat:
                ChatView()
            }
        }
        .animation(.easeInOut, value: appState.currentScreen)
    }
}
