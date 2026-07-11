import SwiftUI

struct LocalModelsView: View {
    @Bindable var model: WeeAppModel
    @State private var registrySearch = ""
    @State private var customRegistryTag = ""
    @State private var customContext = "65536"

    private var selectedCatalogModel: LocalModelCatalogItem? {
        LocalModelCatalogItem.recommended.first { $0.name == model.localModelConfiguration.selectedModel }
    }

    private var filteredModels: [LocalModelCatalogItem] {
        let query = registrySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return LocalModelCatalogItem.recommended }
        return LocalModelCatalogItem.recommended.filter {
            $0.name.lowercased().contains(query)
                || $0.displayName.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    title: "Local Models",
                    subtitle: "Run long-context agent models directly on this Mac",
                    symbol: "cpu"
                ) {
                    Button { Task { await model.refreshOllamaStatus() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(WeeGhostButtonStyle())
                }

                HStack(alignment: .top, spacing: 14) {
                    runnerCard
                    bridgeCard
                }

                registrySearchCard

                Text("64K+ CONTEXT MODEL LIBRARY")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(WeeTheme.textMuted)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(filteredModels) { item in
                        modelCard(item)
                    }
                }

                if !model.ollamaModels.isEmpty {
                    downloadedCard
                }
            }
            .padding(18)
        }
        .task { await model.refreshOllamaStatus() }
    }

    private var runnerCard: some View {
        LocalModelSection(title: "Ollama Runner", systemImage: "bolt.cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusPill(
                        text: model.ollamaStatus,
                        color: model.ollamaStatus.hasPrefix("Running") ? WeeTheme.accent : WeeTheme.gold
                    )
                    Spacer()
                    if model.isOllamaWorking { ProgressView().controlSize(.small) }
                }

                Text("Ollama is the on-device model runner. It provides a local OpenAI-compatible endpoint without sending prompts off this Mac.")
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)

                HStack {
                    if !model.isOllamaInstalled {
                        Button { Task { await model.installOllama() } } label: {
                            Label("Install Ollama", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(WeePrimaryButtonStyle())
                    } else if !model.ollamaStatus.hasPrefix("Running") {
                        Button { Task { await model.startOllama() } } label: {
                            Label("Start Runner", systemImage: "play.fill")
                        }
                        .buttonStyle(WeePrimaryButtonStyle())
                    } else {
                        Button { model.stopOllama() } label: {
                            Label("Stop Runner", systemImage: "stop.fill")
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                    }

                    Toggle("Start with Wee", isOn: $model.localModelConfiguration.autoStartRunner)
                        .toggleStyle(.switch)
                        .font(.caption.weight(.semibold))
                        .onChange(of: model.localModelConfiguration.autoStartRunner) { model.saveConfiguration() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bridgeCard: some View {
        LocalModelSection(title: "Local API Bridge", systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.textMuted)
                Text(selectedCatalogModel?.displayName ?? (model.localModelConfiguration.selectedModel.isEmpty ? "No model selected" : model.localModelConfiguration.selectedModel))
                    .font(.headline)
                    .foregroundStyle(WeeTheme.textPrimary)
                Text(model.localModelConfiguration.selectedModel.isEmpty
                     ? "Download a 64K+ model, then select it to make it the default for the Local API’s `wee` runtime."
                     : "The Local API is launched with `WEE_OLLAMA_HOST=http://127.0.0.1:11434` and uses `ollama/\(model.localModelConfiguration.selectedModel)` for the `wee` runtime.")
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Set a Local agent’s runtime to `wee` to use this model. Selecting a different model restarts the Local API when it is running.")
                    .font(.caption2)
                    .foregroundStyle(WeeTheme.gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var registrySearchCard: some View {
        LocalModelSection(title: "Ollama Registry Search", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search verified registry models", text: $registrySearch)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    TextField("Any registry tag, e.g. org/model:tag", text: $customRegistryTag)
                        .textFieldStyle(.roundedBorder)
                    TextField("Context", text: $customContext)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                    Button("Download") {
                        Task {
                            await model.pullCustomOllamaModel(
                                tag: customRegistryTag,
                                declaredContextWindow: Int(customContext) ?? 0
                            )
                        }
                    }
                    .buttonStyle(WeePrimaryButtonStyle())
                    .disabled(!model.isOllamaInstalled || model.isOllamaWorking)
                }
                HStack {
                    Text("Custom tags require a declared 64K+ context window before download.")
                    Spacer()
                    Link("Browse full registry", destination: URL(string: "https://ollama.com/search")!)
                }
                .font(.caption)
                .foregroundStyle(WeeTheme.textSecondary)
            }
        }
    }

    private func modelCard(_ item: LocalModelCatalogItem) -> some View {
        let isDownloaded = model.ollamaModels.contains { $0.name == item.name }
        let isSelected = model.localModelConfiguration.selectedModel == item.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.headline)
                        .foregroundStyle(WeeTheme.textPrimary)
                    Text("\(item.parameterSize) · \(item.contextWindow / 1_000)K context · ~\(item.estimatedDownloadGB, specifier: "%.0f") GB")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WeeTheme.accent)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(WeeTheme.accent) }
            }
            Text(item.description)
                .font(.caption)
                .foregroundStyle(WeeTheme.textSecondary)
                .lineLimit(2)
            HStack {
                if isDownloaded {
                    if isSelected {
                        Button("Selected") {}
                            .buttonStyle(WeeGhostButtonStyle())
                            .disabled(true)
                    } else {
                        Button("Use Model") { model.selectLocalModel(item) }
                            .buttonStyle(WeePrimaryButtonStyle())
                    }
                } else {
                    Button { Task { await model.pullOllamaModel(item) } } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(WeePrimaryButtonStyle())
                    .disabled(!model.isOllamaInstalled || model.isOllamaWorking)
                }
                Spacer()
                Text(memoryFitLabel(for: item))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(memoryFitColor(for: item))
            }
        }
        .padding(14)
        .background(isSelected ? WeeTheme.accent.opacity(0.08) : WeeTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? WeeTheme.accent.opacity(0.5) : WeeTheme.glassStroke))
    }

    private func memoryFitLabel(for item: LocalModelCatalogItem) -> String {
        let ratio = item.estimatedDownloadGB / model.localModelMemoryGB
        if ratio <= 0.5 { return "Recommended fit" }
        if ratio <= 0.75 { return "Memory pressure" }
        return "Too large for this Mac"
    }

    private func memoryFitColor(for item: LocalModelCatalogItem) -> Color {
        let ratio = item.estimatedDownloadGB / model.localModelMemoryGB
        if ratio <= 0.5 { return WeeTheme.accent }
        return ratio <= 0.75 ? WeeTheme.gold : WeeTheme.danger
    }

    private var downloadedCard: some View {
        LocalModelSection(title: "Downloaded Models", systemImage: "externaldrive.fill") {
            VStack(spacing: 0) {
                ForEach(model.ollamaModels) { downloaded in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(downloaded.name).font(.subheadline.weight(.semibold))
                            Text(downloaded.sizeLabel).font(.caption).foregroundStyle(WeeTheme.textMuted)
                        }
                        Spacer()
                        Button(role: .destructive) { Task { await model.removeOllamaModel(downloaded) } } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                    }
                    .padding(.vertical, 8)
                    if downloaded.id != model.ollamaModels.last?.id { Divider().overlay(WeeTheme.divider) }
                }
            }
        }
    }
}

private struct LocalModelSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WeeTheme.textPrimary)
            content
        }
        .padding(15)
        .background(WeeTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}
