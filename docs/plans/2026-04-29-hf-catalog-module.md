# HF Model Catalog Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Hugging Face model catalog browser ("Discover" mode) alongside the existing backup dashboard, with search, filter, pagination, and detail view — download wired to the backup drive but deferred to a later iteration.

**Architecture:** A top-level mode switcher in ContentView toggles between Backup (existing DashboardView) and Discover (new CatalogView). Discover mode uses its own CatalogViewModel (owned by AppModel) with a new HFModelCatalogService and HFEndpointConfigStore behind it. Domain types live in a standalone Domain file; services in protocol+impl pairs; UI under UI/Catalog/.

**Tech Stack:** SwiftUI, Swift Concurrency, UserDefaults for endpoint config, HF API (unauthenticated)

---

### Task 1: Commit the current branch changes

**Files:** (already staged on `codex/backup-plan-preview`)

The three files on this branch are safe to land before the catalog module:
- `ModeruBakappu/Services/BookmarkStore.swift`
- `ModeruBakappu/UI/DashboardView.swift`
- `ModeruBakappuTests/BookmarkStoreTests.swift`

**Step 1: Commit**

```bash
git add ModeruBakappu/Services/BookmarkStore.swift ModeruBakappu/UI/DashboardView.swift ModeruBakappuTests/BookmarkStoreTests.swift
git commit -m "Add model action plan preview and bookmark path fallback

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 2: Domain Types

**Files:**
- Create: `ModeruBakappu/Domain/HFModelCatalogTypes.swift`

**Step 1: Write the domain types**

```swift
//
//  HFModelCatalogTypes.swift
//  ModeruBakappu
//

import Foundation

enum HFModelFormat: String, CaseIterable {
    case gguf = "gguf"
    case mlx = "mlx"
}

enum HFModelSortField: String, CaseIterable {
    case downloads = "downloads"
    case likes = "likes"
    case lastModified = "lastModified"
    case trending = "trending"
}

struct HFSearchFilter: Equatable {
    var searchQuery: String
    var formatFilter: HFModelFormat?
    var sortField: HFModelSortField
    var ascending: Bool

    static let `default` = HFSearchFilter(
        searchQuery: "",
        formatFilter: nil,
        sortField: .downloads,
        ascending: false
    )
}

struct HFModelFile: Identifiable, Equatable, Decodable {
    let filename: String
    let sizeBytes: Int64

    var id: String { filename }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct HFModelCatalogItem: Identifiable, Equatable {
    let id: String
    let author: String
    let modelName: String
    let pipelineTag: String?
    let tags: [String]
    let files: [HFModelFile]
    let downloads: Int
    let likes: Int
    let lastModified: Date
    let safetensorsAvailable: Bool

    var displayTitle: String { "\(author)/\(modelName)" }

    var formattedDownloads: String {
        if downloads >= 1_000_000 {
            return String(format: "%.1fM", Double(downloads) / 1_000_000.0)
        } else if downloads >= 1_000 {
            return String(format: "%.1fK", Double(downloads) / 1_000.0)
        }
        return "\(downloads)"
    }

    var formattedLikes: String {
        if likes >= 1_000 {
            return String(format: "%.1fK", Double(likes) / 1_000.0)
        }
        return "\(likes)"
    }
}
```

**Step 2: Add the file to the Xcode project**

In Xcode: drag `ModeruBakappu/Domain/HFModelCatalogTypes.swift` into the ModeruBakappu group under Domain/. Or use:

```bash
# Verify the file compiles when added to the target; Xcode project management is manual
```

**Step 3: Commit**

```bash
git add ModeruBakappu/Domain/HFModelCatalogTypes.swift
git commit -m "Add HF model catalog domain types

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 3: HFEndpointConfigStore

**Files:**
- Create: `ModeruBakappu/Services/HFEndpointConfigStore.swift`

The store persists the HF API endpoint URL to UserDefaults. On first launch, it scans `~/.zshrc` and `~/.bashrc` for `export HF_ENDPOINT=` using a simple regex, and surfaces the matched value so the UI can prompt the user to confirm before adopting it.

**Step 1: Write the store**

```swift
//
//  HFEndpointConfigStore.swift
//  ModeruBakappu
//

import Foundation

struct HFEndpointConfig: Equatable {
    var endpointURL: URL
    var isDefault: Bool

    static let defaultEndpoint = URL(string: "https://huggingface.co/api")!
    static let defaultsKey = "ModeruBakappu.hfEndpoint"
}

@MainActor
final class HFEndpointConfigStore {
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func loadEndpointConfig() -> HFEndpointConfig {
        guard let stored = defaults.string(forKey: HFEndpointConfig.defaultsKey),
              let url = URL(string: stored)
        else {
            return HFEndpointConfig(endpointURL: HFEndpointConfig.defaultEndpoint, isDefault: true)
        }
        return HFEndpointConfig(endpointURL: url, isDefault: false)
    }

    func saveEndpointConfig(_ config: HFEndpointConfig) {
        defaults.set(config.endpointURL.absoluteString, forKey: HFEndpointConfig.defaultsKey)
    }

    func scanShellForHFEndpoint() -> String? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".zshrc"),
            home.appendingPathComponent(".bashrc")
        ]
        let pattern = try? NSRegularExpression(
            pattern: #"export\s+HF_ENDPOINT\s*=\s*(.+)"#,
            options: []
        )

        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                guard let match = pattern?.firstMatch(
                    in: line,
                    options: [],
                    range: NSRange(line.startIndex..., in: line)
                ) else { continue }
                guard let range = Range(match.range(at: 1), in: line) else { continue }
                let value = String(line[range])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                guard !value.isEmpty else { continue }
                print("[HFEndpointConfigStore] found HF_ENDPOINT in \(candidate.lastPathComponent): \(value)")
                return value
            }
        }
        return nil
    }

    func hasPromptedForShellImport() -> Bool {
        defaults.bool(forKey: "ModeruBakappu.hfEndpointShellPrompted")
    }

    func markShellImportPrompted() {
        defaults.set(true, forKey: "ModeruBakappu.hfEndpointShellPrompted")
    }
}
```

**Step 2: Commit**

```bash
git add ModeruBakappu/Services/HFEndpointConfigStore.swift
git commit -m "Add HFEndpointConfigStore with shell env scan

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 4: HFModelCatalogService

**Files:**
- Create: `ModeruBakappu/Services/HFModelCatalogService.swift`

Protocol + implementation that calls the HF API. Builds URL from the configured endpoint, appends query params, parses JSON into `[HFModelCatalogItem]`. No authentication.

**Step 1: Write the service**

```swift
//
//  HFModelCatalogService.swift
//  ModeruBakappu
//

import Foundation

enum HFModelCatalogError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case unexpectedResponse(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The search URL could not be constructed."
        case let .networkError(error):
            return "Network request failed: \(error.localizedDescription)"
        case let .unexpectedResponse(statusCode):
            return "Server returned HTTP \(statusCode)."
        case let .decodingError(error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

protocol HFModelCatalogServiceProtocol {
    func searchModels(filter: HFSearchFilter, page: Int, endpoint: URL) async throws -> (items: [HFModelCatalogItem], hasMore: Bool)
}

final class HFModelCatalogService: HFModelCatalogServiceProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func searchModels(filter: HFSearchFilter, page: Int, endpoint: URL) async throws -> (items: [HFModelCatalogItem], hasMore: Bool) {
        guard var components = URLComponents(url: endpoint.appendingPathComponent("models"), resolvingAgainstBaseURL: false) else {
            throw HFModelCatalogError.invalidURL
        }

        var queryItems: [URLQueryItem] = []
        if !filter.searchQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: filter.searchQuery))
        }
        if let format = filter.formatFilter {
            queryItems.append(URLQueryItem(name: "filter", value: format.rawValue))
        }
        queryItems.append(URLQueryItem(name: "sort", value: filter.sortField.rawValue))
        queryItems.append(URLQueryItem(name: "direction", value: filter.ascending ? "1" : "-1"))
        queryItems.append(URLQueryItem(name: "limit", value: "20"))
        queryItems.append(URLQueryItem(name: "offset", value: "\(page * 20)"))

        components.queryItems = queryItems

        guard let url = components.url else {
            throw HFModelCatalogError.invalidURL
        }

        print("[HFModelCatalogService] fetching: \(url.absoluteString)")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HFModelCatalogError.unexpectedResponse(0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HFModelCatalogError.unexpectedResponse(httpResponse.statusCode)
        }

        do {
            let rawItems = try decoder.decode([HFAPIModelItem].self, from: data)
            let items = rawItems.map(HFModelCatalogItem.init(from:))
            return (items, items.count >= 20)
        } catch {
            throw HFModelCatalogError.decodingError(error)
        }
    }
}

// MARK: - Raw API response types (private to this file)

private struct HFAPIModelItem: Decodable {
    let id: String
    let author: String?
    let modelId: String?
    let pipelineTag: String?
    let tags: [String]?
    let siblings: [HFAPISibling]?
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let safetensors: HFAPISafetensors?

    struct HFAPISibling: Decodable {
        let rfilename: String
        let size: Int64?
    }

    struct HFAPISafetensors: Decodable {
        let parameters: [String: [String]]?
    }
}

private extension HFModelCatalogItem {
    init(from raw: HFAPIModelItem) {
        let modelID = raw.modelId ?? raw.id
        let components = modelID.split(separator: "/", maxSplits: 1).map(String.init)
        let author = components.count > 1 ? components[0] : (raw.author ?? "unknown")
        let modelName = components.count > 1 ? components[1] : modelID

        let allTags = raw.tags ?? []
        let fileFormats: [HFModelFile] = (raw.siblings ?? []).compactMap { sibling in
            guard let size = sibling.size else { return nil }
            return HFModelFile(filename: sibling.rfilename, sizeBytes: size)
        }

        let isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date: Date
        if let raw = raw.lastModified {
            date = isoDateFormatter.date(from: raw)
                ?? ISO8601DateFormatter().date(from: raw)
                ?? Date.distantPast
        } else {
            date = Date.distantPast
        }

        self.init(
            id: modelID,
            author: author,
            modelName: modelName,
            pipelineTag: raw.pipelineTag,
            tags: allTags,
            files: fileFormats,
            downloads: raw.downloads ?? 0,
            likes: raw.likes ?? 0,
            lastModified: date,
            safetensorsAvailable: raw.safetensors?.parameters != nil
        )
    }
}
```

**Step 2: Commit**

```bash
git add ModeruBakappu/Services/HFModelCatalogService.swift
git commit -m "Add HFModelCatalogService with HF API search

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 5: CatalogViewModel

**Files:**
- Create: `ModeruBakappu/UI/Catalog/CatalogViewModel.swift`

Separate `@MainActor ObservableObject` owned by `AppModel`. Holds search state, pagination, results, selection. Depends on `HFModelCatalogServiceProtocol` and `HFEndpointConfigStore` for the endpoint URL.

**Step 1: Write CatalogViewModel**

```swift
//
//  CatalogViewModel.swift
//  ModeruBakappu
//

import SwiftUI

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var filter = HFSearchFilter.default
    @Published var items: [HFModelCatalogItem] = []
    @Published var selectedItem: HFModelCatalogItem?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMorePages = false
    @Published var shellEndpointCandidate: String?

    private let service: HFModelCatalogServiceProtocol
    private let endpointStore: HFEndpointConfigStore
    private var currentPage = 0
    private var searchTask: Task<Void, Never>?

    var endpointConfig: HFEndpointConfig {
        endpointStore.loadEndpointConfig()
    }

    var showShellEndpointPrompt: Bool {
        shellEndpointCandidate != nil && !endpointStore.hasPromptedForShellImport()
    }

    init(
        service: HFModelCatalogServiceProtocol = HFModelCatalogService(),
        endpointStore: HFEndpointConfigStore = HFEndpointConfigStore()
    ) {
        self.service = service
        self.endpointStore = endpointStore
    }

    func onAppear() {
        shellEndpointCandidate = endpointStore.scanShellForHFEndpoint()
    }

    func adoptShellEndpoint() {
        guard let candidate = shellEndpointCandidate,
              let url = URL(string: candidate)
        else { return }
        var config = endpointConfig
        config.endpointURL = url
        config.isDefault = false
        endpointStore.saveEndpointConfig(config)
        shellEndpointCandidate = nil
        endpointStore.markShellImportPrompted()
    }

    func dismissShellEndpointPrompt() {
        shellEndpointCandidate = nil
        endpointStore.markShellImportPrompted()
    }

    func search() {
        searchTask?.cancel()
        currentPage = 0

        searchTask = Task {
            await performSearch(page: 0)
        }
    }

    func loadMoreIfNeeded(currentItem: HFModelCatalogItem) {
        guard !isLoading, hasMorePages else { return }
        let threshold = items.suffix(5)
        guard threshold.contains(where: { $0.id == currentItem.id }) else { return }

        searchTask?.cancel()
        searchTask = Task {
            await performSearch(page: currentPage + 1)
        }
    }

    func selectItem(_ item: HFModelCatalogItem?) {
        selectedItem = item
    }

    func dismissError() {
        errorMessage = nil
    }

    private func performSearch(page: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            let config = endpointConfig
            let result = try await service.searchModels(
                filter: filter,
                page: page,
                endpoint: config.endpointURL
            )

            guard !Task.isCancelled else { return }

            if page == 0 {
                items = result.items
            } else {
                items.append(contentsOf: result.items)
            }
            currentPage = page
            hasMorePages = result.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
```

**Step 2: Commit**

```bash
git add ModeruBakappu/UI/Catalog/CatalogViewModel.swift
git commit -m "Add CatalogViewModel for HF model search state

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 6: CatalogModelRow and CatalogModelDetail

**Files:**
- Create: `ModeruBakappu/UI/Catalog/CatalogModelRow.swift`
- Create: `ModeruBakappu/UI/Catalog/CatalogModelDetail.swift`

**Step 1: Write CatalogModelRow**

```swift
//
//  CatalogModelRow.swift
//  ModeruBakappu
//

import SwiftUI

struct CatalogModelRow: View {
    let item: HFModelCatalogItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.modelName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                if let pipelineTag = item.pipelineTag {
                    Text(pipelineTag)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                if item.tags.contains("gguf") {
                    Text("GGUF")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                if item.safetensorsAvailable {
                    Text("Safe")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 0)

                Label(item.formattedDownloads, systemImage: "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
```

**Step 2: Write CatalogModelDetail**

```swift
//
//  CatalogModelDetail.swift
//  ModeruBakappu
//

import SwiftUI

struct CatalogModelDetail: View {
    let item: HFModelCatalogItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.modelName)
                        .font(.title2.weight(.semibold))
                    Text(item.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 16) {
                    StatLabel(title: "Downloads", value: item.formattedDownloads)
                    StatLabel(title: "Likes", value: item.formattedLikes)
                    StatLabel(title: "Updated", value: item.lastModified.formatted(date: .abbreviated, time: .omitted))
                }

                if let pipelineTag = item.pipelineTag {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pipeline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(pipelineTag)
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                if !item.files.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Files")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 6) {
                            ForEach(item.files) { file in
                                FileRow(file: file)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }
}

private struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FileRow: View {
    let file: HFModelFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.sizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Download") {
                // Deferred to next iteration
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
            .help("Download to the backup drive. Requires the backup drive to be online and writable.")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}
```

**Step 3: Commit**

```bash
git add ModeruBakappu/UI/Catalog/CatalogModelRow.swift ModeruBakappu/UI/Catalog/CatalogModelDetail.swift
git commit -m "Add catalog model row and detail views

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 7: CatalogView

**Files:**
- Create: `ModeruBakappu/UI/Catalog/CatalogView.swift`

Two-panel layout: searchable model list on left, detail on right. Auto-loads more on scroll near bottom. Empty state when no results or no selection.

**Step 1: Write CatalogView**

```swift
//
//  CatalogView.swift
//  ModeruBakappu
//

import SwiftUI

struct CatalogView: View {
    @ObservedObject var viewModel: CatalogViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                modelList
                    .frame(width: 340)

                Divider()

                detailPanel
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .alert("HF Endpoint Detected", isPresented: shellEndpointBinding) {
            Button("Use Detected") { viewModel.adoptShellEndpoint() }
            Button("Ignore") { viewModel.dismissShellEndpointPrompt() }
        } message: {
            Text("Found \"\(viewModel.shellEndpointCandidate ?? "")\" in your shell config. Use this as the Hugging Face API endpoint?")
        }
        .alert("Search Error", isPresented: errorBinding) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: searchBinding)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        viewModel.search()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            Picker("Format", selection: formatBinding) {
                Text("All Formats").tag(HFModelFormat?.none)
                Text("GGUF").tag(HFModelFormat?.some(.gguf))
                Text("MLX").tag(HFModelFormat?.some(.mlx))
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("Sort", selection: sortBinding) {
                ForEach(HFModelSortField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Button {
                viewModel.search()
            } label: {
                Text("Search")
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var modelList: some View {
        Group {
            if viewModel.items.isEmpty {
                VStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView("Searching...")
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Search Hugging Face models")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.items) { item in
                            CatalogModelRow(
                                item: item,
                                isSelected: viewModel.selectedItem?.id == item.id
                            )
                            .onTapGesture {
                                viewModel.selectItem(item)
                            }
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentItem: item)
                            }

                            Divider()
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedItem = viewModel.selectedItem {
            CatalogModelDetail(item: selectedItem)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.leadinghalf.inset.filled")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select a model to see details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bindings

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.filter.searchQuery },
            set: { viewModel.filter.searchQuery = $0 }
        )
    }

    private var formatBinding: Binding<HFModelFormat?> {
        Binding(
            get: { viewModel.filter.formatFilter },
            set: { viewModel.filter.formatFilter = $0 }
        )
    }

    private var sortBinding: Binding<HFModelSortField> {
        Binding(
            get: { viewModel.filter.sortField },
            set: { viewModel.filter.sortField = $0 }
        )
    }

    private var shellEndpointBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showShellEndpointPrompt },
            set: { _ in }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }
}

private extension HFModelSortField {
    var displayName: String {
        switch self {
        case .downloads: return "Downloads"
        case .likes: return "Likes"
        case .lastModified: return "Last Modified"
        case .trending: return "Trending"
        }
    }
}
```

**Step 2: Commit**

```bash
git add ModeruBakappu/UI/Catalog/CatalogView.swift
git commit -m "Add CatalogView with two-panel search and detail

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 8: Wire CatalogViewModel into AppModel and add mode switcher to ContentView

**Files:**
- Modify: `ModeruBakappu/App/AppModel.swift` — add `catalogViewModel` property
- Modify: `ModeruBakappu/UI/ContentView.swift` — add Backup/Discover mode switcher

**Step 1: Add catalogViewModel to AppModel**

In `AppModel.swift`, add after the existing `@Published` properties:

```swift
let catalogViewModel = CatalogViewModel()
```

**Step 2: Rewrite ContentView with mode switcher**

Replace `ContentView.swift`:

```swift
//
//  ContentView.swift
//  ModeruBakappu
//

import SwiftUI

enum AppMode: String, CaseIterable {
    case backup = "Backup"
    case discover = "Discover"

    var systemImage: String {
        switch self {
        case .backup: return "externaldrive"
        case .discover: return "magnifyingglass"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedMode: AppMode = .backup

    var body: some View {
        Group {
            if !appModel.hasLoaded {
                ProgressView("Loading configuration…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appModel.hasMinimumConfiguration {
                VStack(spacing: 0) {
                    modeSwitcher
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .underPageBackgroundColor))

                    Divider()

                    switch selectedMode {
                    case .backup:
                        DashboardView()
                    case .discover:
                        CatalogView(viewModel: appModel.catalogViewModel)
                    }
                }
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert("Configuration Error", isPresented: alertBinding) {
            Button("OK") {
                appModel.clearError()
            }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.caption)
                        Text(mode.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        selectedMode == mode
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .foregroundStyle(
                        selectedMode == mode
                            ? Color.accentColor
                            : Color.secondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { appModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appModel.clearError()
                }
            }
        )
    }
}
```

Key changes:
- New `AppMode` enum with `.backup` and `.discover`
- Segmented control-style mode switcher at top
- Minimum width bumped from 760 to 900 to accommodate the two-panel catalog layout
- `CatalogView` receives `appModel.catalogViewModel`

**Step 3: Verify build compiles**

Open the Xcode project, ensure all new files are added to the target, and build:

```bash
xcodebuild -project ModeruBakappu.xcodeproj -scheme ModeruBakappu -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add ModeruBakappu/App/AppModel.swift ModeruBakappu/UI/ContentView.swift
git commit -m "Add Backup/Discover mode switcher and wire CatalogViewModel

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 9: Write CatalogViewModel tests

**Files:**
- Create: `ModeruBakappuTests/CatalogViewModelTests.swift`

Test the search, pagination, selection, and shell endpoint flow using a mock service.

**Step 1: Write the tests**

```swift
//
//  CatalogViewModelTests.swift
//  ModeruBakappuTests
//

import XCTest
@testable import ModeruBakappu

private final class MockCatalogService: HFModelCatalogServiceProtocol {
    var result: Result<(items: [HFModelCatalogItem], hasMore: Bool), Error> = .success(([], false))
    var lastFilter: HFSearchFilter?
    var lastPage: Int?
    var lastEndpoint: URL?

    func searchModels(filter: HFSearchFilter, page: Int, endpoint: URL) async throws -> (items: [HFModelCatalogItem], hasMore: Bool) {
        lastFilter = filter
        lastPage = page
        lastEndpoint = endpoint
        return try result.get()
    }
}

final class CatalogViewModelTests: XCTestCase {
    private var mockService: MockCatalogService!
    private var endpointStore: HFEndpointConfigStore!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "CatalogViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        mockService = MockCatalogService()
        endpointStore = HFEndpointConfigStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        mockService = nil
        endpointStore = nil
        defaults = nil
        suiteName = nil
    }

    func testSearchPopulatesItems() async throws {
        let items = createSampleItems(count: 3)
        mockService.result = .success((items, false))

        let viewModel = CatalogViewModel(service: mockService, endpointStore: endpointStore)
        viewModel.search()

        // Wait for async search to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(viewModel.items.count, 3)
        XCTAssertEqual(viewModel.items[0].id, "author0/model0")
        XCTAssertFalse(viewModel.hasMorePages)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadMoreAppendsItems() async throws {
        let firstPage = createSampleItems(count: 3, offset: 0)
        let secondPage = createSampleItems(count: 2, offset: 3)
        mockService.result = .success((firstPage, true))

        let viewModel = CatalogViewModel(service: mockService, endpointStore: endpointStore)
        viewModel.search()
        try await Task.sleep(nanoseconds: 200_000_000)

        mockService.result = .success((secondPage, false))
        viewModel.loadMoreIfNeeded(currentItem: viewModel.items.last!)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(viewModel.items.count, 5)
        XCTAssertFalse(viewModel.hasMorePages)
    }

    func testSelectItemUpdatesSelection() {
        let viewModel = CatalogViewModel(service: mockService, endpointStore: endpointStore)
        let item = createSampleItems(count: 1)[0]

        viewModel.selectItem(item)
        XCTAssertEqual(viewModel.selectedItem?.id, "author0/model0")

        viewModel.selectItem(nil)
        XCTAssertNil(viewModel.selectedItem)
    }

    func testSearchErrorIsSurfaced() async throws {
        mockService.result = .failure(HFModelCatalogError.unexpectedResponse(500))

        let viewModel = CatalogViewModel(service: mockService, endpointStore: endpointStore)
        viewModel.search()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testAdoptShellEndpointSavesConfig() {
        let viewModel = CatalogViewModel(service: mockService, endpointStore: endpointStore)
        viewModel.shellEndpointCandidate = "https://hf-mirror.com/api"

        viewModel.adoptShellEndpoint()

        let config = endpointStore.loadEndpointConfig()
        XCTAssertEqual(config.endpointURL.absoluteString, "https://hf-mirror.com/api")
        XCTAssertFalse(config.isDefault)
        XCTAssertTrue(endpointStore.hasPromptedForShellImport())
    }

    func testDismissShellPromptMarksPrompted() {
        let viewModel = CatalogViewModel(service: mockService, endpointStore: endpointStore)
        viewModel.shellEndpointCandidate = "https://hf-mirror.com/api"

        viewModel.dismissShellEndpointPrompt()

        XCTAssertNil(viewModel.shellEndpointCandidate)
        XCTAssertTrue(endpointStore.hasPromptedForShellImport())
    }

    // MARK: - Helpers

    private func createSampleItems(count: Int, offset: Int = 0) -> [HFModelCatalogItem] {
        (0..<count).map { i in
            let idx = offset + i
            return HFModelCatalogItem(
                id: "author\(idx)/model\(idx)",
                author: "author\(idx)",
                modelName: "model\(idx)",
                pipelineTag: "text-generation",
                tags: ["gguf"],
                files: [
                    HFModelFile(filename: "model-q4_k_m.gguf", sizeBytes: 5_000_000_000)
                ],
                downloads: 1000 * idx,
                likes: 100 * idx,
                lastModified: Date(),
                safetensorsAvailable: true
            )
        }
    }
}
```

**Step 2: Run tests**

```bash
xcodebuild test -project ModeruBakappu.xcodeproj -scheme ModeruBakappu -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all new tests pass.

**Step 3: Commit**

```bash
git add ModeruBakappuTests/CatalogViewModelTests.swift
git commit -m "Add CatalogViewModel tests

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 10: Final integration test and review

**Step 1: Run the full test suite**

```bash
xcodebuild test -project ModeruBakappu.xcodeproj -scheme ModeruBakappu -destination 'platform=macOS' 2>&1 | grep -E '(TEST SUCCEEDED|TEST FAILED|passed|failed)'
```

Expected: All tests pass.

**Step 2: Launch the app and verify**

1. Build and run from Xcode
2. Verify the mode switcher appears after onboarding
3. Switch to "Discover" mode
4. Enter a search query and verify results load
5. Click a model to see its detail panel
6. Verify the "Download" buttons are present but disabled
7. Switch back to "Backup" mode — verify DashboardView is unchanged

**Step 3: Commit any final tweaks**

```bash
git commit -m "Final integration verification for HF catalog module

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Summary

**New files (7):**
- `ModeruBakappu/Domain/HFModelCatalogTypes.swift`
- `ModeruBakappu/Services/HFEndpointConfigStore.swift`
- `ModeruBakappu/Services/HFModelCatalogService.swift`
- `ModeruBakappu/UI/Catalog/CatalogViewModel.swift`
- `ModeruBakappu/UI/Catalog/CatalogModelRow.swift`
- `ModeruBakappu/UI/Catalog/CatalogModelDetail.swift`
- `ModeruBakappu/UI/Catalog/CatalogView.swift`
- `ModeruBakappuTests/CatalogViewModelTests.swift`

**Modified files (2):**
- `ModeruBakappu/App/AppModel.swift` — add `catalogViewModel` property
- `ModeruBakappu/UI/ContentView.swift` — add mode switcher and CatalogView routing

**Deferred to next iteration:**
- Actual file download via `HFModelCatalogService.downloadFile(...)`
- `AppModel.downloadFromCatalog(...)` method
- Provider-format compatibility hints (LM Studio → GGUF, oMLX → MLX)
- Download progress tracking
