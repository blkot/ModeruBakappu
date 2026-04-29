//
//  CatalogViewModel.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    // MARK: - Published State

    @Published var searchQuery = ""
    @Published var formatFilter: HFModelFormat? = nil
    @Published var sortField: HFModelSortField = .downloads
    @Published var ascending = false
    @Published var items: [HFModelCatalogItem] = []
    @Published var selectedItem: HFModelCatalogItem? = nil
    @Published var isLoading = false
    @Published var hasMorePages = true
    @Published var errorMessage: String? = nil
    @Published var shellEndpointCandidate: String? = nil

    // MARK: - Computed Properties

    var endpointConfig: HFEndpointConfig {
        endpointStore.loadEndpointConfig()
    }

    var showShellEndpointPrompt: Bool {
        shellEndpointCandidate != nil && !endpointStore.hasPromptedForShellImport()
    }

    var currentFilter: HFSearchFilter {
        HFSearchFilter(
            searchQuery: searchQuery,
            formatFilter: formatFilter,
            sortField: sortField,
            ascending: ascending
        )
    }

    // MARK: - Dependencies

    private let service: HFModelCatalogServiceProtocol
    private let endpointStore: HFEndpointConfigStore

    // MARK: - Internal State

    private var currentPage = 0
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        service: HFModelCatalogServiceProtocol? = nil,
        endpointStore: HFEndpointConfigStore? = nil
    ) {
        self.service = service ?? HFModelCatalogService()
        self.endpointStore = endpointStore ?? HFEndpointConfigStore()
    }

    // MARK: - Lifecycle

    func onAppear() {
        shellEndpointCandidate = endpointStore.scanShellForHFEndpoint()
    }

    // MARK: - Shell Endpoint

    func adoptShellEndpoint() {
        guard let candidate = shellEndpointCandidate,
              let url = URL(string: candidate)
        else { return }

        let config = HFEndpointConfig(endpointURL: url, isDefault: false)
        endpointStore.saveEndpointConfig(config)
        endpointStore.markShellImportPrompted()
        shellEndpointCandidate = nil
        objectWillChange.send()
    }

    func dismissShellEndpointPrompt() {
        endpointStore.markShellImportPrompted()
        shellEndpointCandidate = nil
    }

    // MARK: - Search

    func search() {
        searchTask?.cancel()
        currentPage = 0
        items = []
        hasMorePages = true
        errorMessage = nil

        searchTask = Task { [weak self] in
            await self?.performSearch(page: 0)
        }
    }

    // MARK: - Pagination

    func loadMoreIfNeeded(currentItem: HFModelCatalogItem) {
        guard !isLoading, hasMorePages else { return }
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= items.count - 5 else { return }

        let nextPage = currentPage + 1
        isLoading = true
        searchTask?.cancel()

        searchTask = Task { [weak self] in
            await self?.performSearch(page: nextPage)
        }
    }

    // MARK: - Selection

    func selectItem(_ item: HFModelCatalogItem?) {
        selectedItem = item
    }

    // MARK: - Internal Search Logic

    private func performSearch(page: Int) async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let result = try await service.searchModels(
                filter: currentFilter,
                page: page,
                endpoint: endpointConfig.endpointURL
            )

            try Task.checkCancellation()

            if page == 0 {
                items = result.items
            } else {
                let existingIDs = Set(items.map(\.id))
                let newItems = result.items.filter { !existingIDs.contains($0.id) }
                items.append(contentsOf: newItems)
            }

            currentPage = page
            hasMorePages = result.hasMore
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
