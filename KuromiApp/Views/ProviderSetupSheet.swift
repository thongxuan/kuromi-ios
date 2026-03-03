import SwiftUI

// MARK: - STT Provider Sheet
struct STTProviderSheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedProvider: STTProvider = .deepgram
    @State private var configs: [String: ProviderConfig] = [:]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Provider picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Provider")
                                .font(.caption).foregroundColor(.gray)
                            HStack(spacing: 10) {
                                ForEach(STTProvider.allCases, id: \.rawValue) { p in
                                    Button(action: { selectedProvider = p }) {
                                        Text(p.displayName)
                                            .font(.subheadline).fontWeight(.medium)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(selectedProvider == p ? Color.purple : Color.white.opacity(0.08))
                                            )
                                            .foregroundColor(selectedProvider == p ? .white : .gray)
                                    }
                                }
                            }
                        }

                        providerFields(for: selectedProvider)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("STT Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var s = AppSettings.load() ?? defaultSettings()
                        s.selectedSTTProvider = selectedProvider
                        for (k, v) in configs { s.sttConfigs[k] = v }
                        s.save()
                        onSave()
                        dismiss()
                    }.foregroundColor(.purple)
                }
            }
        }
        .onAppear {
            if let s = AppSettings.load() {
                selectedProvider = s.selectedSTTProvider
                configs = s.sttConfigs
            }
            // Set default model if missing
            for p in STTProvider.allCases {
                if configs[p.rawValue] == nil {
                    configs[p.rawValue] = ProviderConfig(apiKey: "", model: p.defaultModel)
                }
            }
        }
    }

    @ViewBuilder
    private func providerFields(for provider: STTProvider) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.gray)
                SecureField("Enter API key", text: Binding(
                    get: { configs[provider.rawValue]?.apiKey ?? "" },
                    set: { val in configs[provider.rawValue, default: ProviderConfig(apiKey: "", model: provider.defaultModel)].apiKey = val }
                ))
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.caption).foregroundColor(.gray)
                Picker("Model", selection: Binding(
                    get: { configs[provider.rawValue]?.model ?? provider.defaultModel },
                    set: { val in configs[provider.rawValue, default: ProviderConfig(apiKey: "", model: provider.defaultModel)].model = val }
                )) {
                    ForEach(provider.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .accentColor(.purple)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
        }
    }
}

// MARK: - TTS Provider Sheet
struct TTSProviderSheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedProvider: TTSProvider = .openai
    @State private var configs: [String: ProviderConfig] = [:]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Provider")
                                .font(.caption).foregroundColor(.gray)
                            HStack(spacing: 10) {
                                ForEach(TTSProvider.allCases, id: \.rawValue) { p in
                                    Button(action: { selectedProvider = p }) {
                                        Text(p.displayName)
                                            .font(.subheadline).fontWeight(.medium)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(selectedProvider == p ? Color.purple : Color.white.opacity(0.08))
                                            )
                                            .foregroundColor(selectedProvider == p ? .white : .gray)
                                    }
                                }
                            }
                        }

                        providerFields(for: selectedProvider)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("TTS Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var s = AppSettings.load() ?? defaultSettings()
                        s.selectedTTSProvider = selectedProvider
                        for (k, v) in configs { s.ttsConfigs[k] = v }
                        s.save()
                        onSave()
                        dismiss()
                    }.foregroundColor(.purple)
                }
            }
        }
        .onAppear {
            if let s = AppSettings.load() {
                selectedProvider = s.selectedTTSProvider
                configs = s.ttsConfigs
            }
            for p in TTSProvider.allCases {
                if configs[p.rawValue] == nil {
                    configs[p.rawValue] = ProviderConfig(apiKey: "", model: p.defaultModel)
                }
            }
        }
    }

    @ViewBuilder
    private func providerFields(for provider: TTSProvider) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.gray)
                SecureField("Enter API key", text: Binding(
                    get: { configs[provider.rawValue]?.apiKey ?? "" },
                    set: { val in configs[provider.rawValue, default: ProviderConfig(apiKey: "", model: provider.defaultModel)].apiKey = val }
                ))
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.caption).foregroundColor(.gray)
                Picker("Model", selection: Binding(
                    get: { configs[provider.rawValue]?.model ?? provider.defaultModel },
                    set: { val in configs[provider.rawValue, default: ProviderConfig(apiKey: "", model: provider.defaultModel)].model = val }
                )) {
                    ForEach(provider.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .accentColor(.purple)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
        }
    }
}

private func defaultSettings() -> AppSettings {
    AppSettings(
        gatewayURL: "", gatewayToken: "",
        selectedVoiceID: "", selectedVoiceName: "",
        sttLanguage: "vi", wakeWord: "hey kuromi",
        wakeWordSamples: [], ttsVoice: "nova"
    )
}
