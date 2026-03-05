import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SetupViewModel
    init(isEditMode: Bool = false) {
        _viewModel = StateObject(wrappedValue: SetupViewModel(isEditMode: isEditMode))
    }

    @State private var showGatewaySheet = false
    @State private var showLanguageSheet = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("OpenVoice")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.appLabel)
                    Text(viewModel.isEditMode ? "Edit Settings" : "Set up your assistant")
                        .font(.subheadline)
                        .foregroundColor(.appSecondaryLabel)
                }
                .padding(.top, 48)

                // Setting rows
                VStack(spacing: 12) {
                    SettingRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Gateway",
                        value: viewModel.gatewayURL.isEmpty ? "Not configured" : viewModel.gatewayURL
                    ) { showGatewaySheet = true }

                    SettingRow(
                        icon: "globe",
                        title: "Language",
                        value: {
                            let lang = SetupViewModel.languages.first { $0.code == viewModel.sttLanguage }
                            return "\(lang?.flag ?? "🌐") \(lang?.name ?? viewModel.sttLanguage)"
                        }()
                    ) { showLanguageSheet = true }
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
                                .font(.headline).foregroundColor(.appBackground)
                            Spacer()
                            Image(systemName: "arrow.right").foregroundColor(.appBackground)
                        }
                        .padding(.horizontal, 24)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.appLabel))
                    }
                    .disabled(!viewModel.canContinue)
                    .opacity(viewModel.canContinue ? 1.0 : 0.4)

                    if viewModel.isEditMode {
                        Button("Cancel") { appState.closeSetupEdit() }
                            .font(.headline).foregroundColor(.appSecondaryLabel).frame(height: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .safeAreaPadding()
        // Gateway sheet
        .sheet(isPresented: $showGatewaySheet) {
            GatewaySheet(gatewayURL: $viewModel.gatewayURL, gatewayToken: $viewModel.gatewayToken)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appSheetBackground)
                .presentationBackgroundInteraction(.disabled)
        }
        // Language sheet
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSheet(
                sttLanguage: $viewModel.sttLanguage,
                wakePhrase: $viewModel.wakePhrase,
                stopPhrase: $viewModel.stopPhrase
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appSheetBackground)
            .presentationBackgroundInteraction(.disabled)
        }
    }

    private func continueAction() {
        guard viewModel.save() != nil else { return }
        appState.currentScreen = .chat
    }
}

// MARK: - Setting Row

struct SettingRow: View {
    let icon: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.purple)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.appSecondaryLabel)
                    Text(value)
                        .font(.body)
                        .foregroundColor(.appLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appFieldBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.appBorder, lineWidth: 1))
            )
        }
    }
}

// MARK: - Gateway Sheet

struct GatewaySheet: View {
    @Binding var gatewayURL: String
    @Binding var gatewayToken: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.appSheetBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("Gateway")
                    .font(.title2).bold().foregroundColor(.appLabel)
                    .padding(.top, 8)

                VStack(spacing: 16) {
                    KuromiTextField(
                        title: "Gateway URL",
                        placeholder: "ws://192.168.1.1:18789",
                        text: $gatewayURL,
                        icon: "antenna.radiowaves.left.and.right"
                    )
                    KuromiTextField(
                        title: "Token",
                        placeholder: "leave empty if no auth",
                        text: $gatewayToken,
                        icon: "key.fill",
                        isSecure: true
                    )
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.headline).foregroundColor(.appBackground)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appLabel))
                }
            }
            .padding(24)
        }
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}

// MARK: - Language Sheet

struct LanguageSheet: View {
    @Binding var sttLanguage: String
    @Binding var wakePhrase: String
    @Binding var stopPhrase: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.appSheetBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("Language")
                    .font(.title2).bold().foregroundColor(.appLabel)
                    .padding(.top, 8)

                VStack(spacing: 16) {
                    // Language picker — same shell as KuromiTextField
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "globe").font(.caption).foregroundColor(.purple)
                            Text("Language").font(.caption).fontWeight(.medium).foregroundColor(.appSecondaryLabel)
                        }
                        Menu {
                            ForEach(SetupViewModel.languages, id: \.code) { lang in
                                Button(action: { sttLanguage = lang.code }) {
                                    Label("\(lang.flag) \(lang.name)", systemImage: sttLanguage == lang.code ? "checkmark" : "")
                                }
                            }
                        } label: {
                            HStack {
                                let current = SetupViewModel.languages.first { $0.code == sttLanguage }
                                Text("\(current?.flag ?? "🌐") \(current?.name ?? sttLanguage)")
                                    .foregroundColor(.appLabel).font(.body)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundColor(.appSecondaryLabel)
                            }
                            .padding(.horizontal, 16).frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.appFieldBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.appBorder, lineWidth: 1))
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }

                    KuromiTextField(title: "Wake phrase", placeholder: "e.g. mi ơi", text: $wakePhrase, icon: "waveform")
                    KuromiTextField(title: "Stop phrase", placeholder: "e.g. thôi nhé", text: $stopPhrase, icon: "stop.circle")
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.headline).foregroundColor(.appBackground)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appLabel))
                }
            }
            .padding(24)
        }
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}

// MARK: - Text Field

struct KuromiTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var icon: String = ""
    var isSecure: Bool = false
    var validation: ValidationState = .idle

    @State private var isRevealed = false

    private var borderColor: Color {
        switch validation {
        case .success: return .green.opacity(0.6)
        case .failure: return .red.opacity(0.6)
        default: return Color.appBorder
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !icon.isEmpty {
                    Image(systemName: icon).font(.caption).foregroundColor(.purple)
                }
                Text(title).font(.caption).fontWeight(.medium).foregroundColor(.appSecondaryLabel)
                Spacer()
                switch validation {
                case .checking: ProgressView().scaleEffect(0.7).tint(.gray)
                case .success: Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                case .failure(let msg):
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(msg).foregroundColor(.red)
                    }.font(.caption2)
                case .idle: EmptyView()
                }
            }

            HStack {
                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .autocapitalization(.none).autocorrectionDisabled()
                    }
                }
                .font(.system(.body, design: .monospaced)).foregroundColor(.appLabel)

                if isSecure {
                    Button(action: { isRevealed.toggle() }) {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundColor(.appSecondaryLabel).font(.caption)
                    }
                }
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appFieldBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderColor, lineWidth: 1))
            )
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(AppState())
}
