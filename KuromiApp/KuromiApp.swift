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

    init() {
        isSetupComplete = AppSettings.load() != nil
        if isSetupComplete {
            currentScreen = .chat
        }
    }
}

enum AppScreen: Equatable {
    case setup
    case voiceSetup
    case chat
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .setup:
                SetupView()
            case .voiceSetup:
                VoiceSetupView()
            case .chat:
                ChatView()
            }
        }
        .animation(.easeInOut, value: appState.currentScreen)
    }
}
