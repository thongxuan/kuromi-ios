import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SetupViewModel

    init(isEditMode: Bool = false) {
        _viewModel = StateObject(wrappedValue: SetupViewModel(isEditMode: isEditMode))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("🖤")
                        .font(.system(size: 60))
                    Text("Kuromi")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(viewModel.isEditMode ? "Edit Settings" : "Set up your assistant")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 48)

                // Fields
                VStack(spacing: 16) {
                    KuromiTextField(
                        title: "Gateway URL",
                        placeholder: "ws://192.168.1.1:8080",
                        text: $viewModel.gatewayURL,
                        icon: "antenna.radiowaves.left.and.right"
                    )

                    KuromiTextField(
                        title: "Deepgram API Key",
                        placeholder: "dg_...",
                        text: $viewModel.deepgramAPIKey,
                        icon: "mic.fill",
                        isSecure: true
                    )

                    KuromiTextField(
                        title: "ElevenLabs API Key",
                        placeholder: "sk_...",
                        text: $viewModel.elevenLabsAPIKey,
                        icon: "speaker.wave.2.fill",
                        isSecure: true
                    )
                }
                .padding(.horizontal, 24)

                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button(action: continueAction) {
                        HStack {
                            Text(viewModel.isEditMode ? "Save" : "Continue")
                                .font(.headline)
                                .foregroundColor(.black)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 24)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                        )
                    }
                    .disabled(!viewModel.isValid)
                    .opacity(viewModel.isValid ? 1.0 : 0.4)

                    if viewModel.isEditMode {
                        Button("Cancel") {
                            appState.closeSetupEdit()
                        }
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(height: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func continueAction() {
        guard viewModel.save() != nil else { return }
        if viewModel.isEditMode {
            appState.closeSetupEdit()
        } else {
            appState.currentScreen = .voiceSetup
        }
    }
}

struct KuromiTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var icon: String = ""
    var isSecure: Bool = false

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.purple)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
            }

            HStack {
                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)

                if isSecure {
                    Button(action: { isRevealed.toggle() }) {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(AppState())
}
