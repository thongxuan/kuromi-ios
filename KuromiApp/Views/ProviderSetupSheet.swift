import SwiftUI

// MARK: - STT Provider Sheet
struct STTProviderSheet: View {
    @Binding var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var selectedProvider: STTProvider
    @State private var configs: [String: ProviderConfig]

    init(settings: Binding<AppSettings>) {
        self._settings = settings
        self._selectedProvider = State(initialValue: settings.wrappedValue.selectedSTTProvider)
        self._configs = State(initialValue: settings.wrappedValue.sttConfigs)
    }

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

                        // Config for selected provider
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
                        settings.selectedSTTProvider = selectedProvider
                        settings.sttConfigs = configs
                        settings.save()
                        dismiss()
                    }.foregroundColor(.purple)
                }
            }
        }
    }

    @ViewBuilder
    private func providerFields(for provider: STTProvider) -> some View {
        let binding = configBinding(for: provider.rawValue)
        VStack(alignment: .leading, spacing: 16) {
            // API Key
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.gray)
                SecureField("Enter API key", text: binding.apiKey)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            }
            // Model
            VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.caption).foregroundColor(.gray)
                Picker("Model", selection: binding.model) {
                    ForEach(provider.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .accentColor(.purple)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .onAppear {
                    if binding.model.wrappedValue.isEmpty {
                        binding.model.wrappedValue = provider.defaultModel
                    }
                }
            }
        }
    }

    private func configBinding(for key: String) -> Binding<ProviderConfig> {
        Binding(
            get: { configs[key] ?? ProviderConfig(apiKey: "", model: "") },
            set: { configs[key] = $0 }
        )
    }
}

// MARK: - TTS Provider Sheet
struct TTSProviderSheet: View {
    @Binding var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var selectedProvider: TTSProvider
    @State private var configs: [String: ProviderConfig]

    init(settings: Binding<AppSettings>) {
        self._settings = settings
        self._selectedProvider = State(initialValue: settings.wrappedValue.selectedTTSProvider)
        self._configs = State(initialValue: settings.wrappedValue.ttsConfigs)
    }

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
                        settings.selectedTTSProvider = selectedProvider
                        settings.ttsConfigs = configs
                        settings.save()
                        dismiss()
                    }.foregroundColor(.purple)
                }
            }
        }
    }

    @ViewBuilder
    private func providerFields(for provider: TTSProvider) -> some View {
        let binding = configBinding(for: provider.rawValue)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.caption).foregroundColor(.gray)
                SecureField("Enter API key", text: binding.apiKey)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.caption).foregroundColor(.gray)
                Picker("Model", selection: binding.model) {
                    ForEach(provider.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .accentColor(.purple)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .onAppear {
                    if binding.model.wrappedValue.isEmpty {
                        binding.model.wrappedValue = provider.defaultModel
                    }
                }
            }
        }
    }

    private func configBinding(for key: String) -> Binding<ProviderConfig> {
        Binding(
            get: { configs[key] ?? ProviderConfig(apiKey: "", model: "") },
            set: { configs[key] = $0 }
        )
    }
}
