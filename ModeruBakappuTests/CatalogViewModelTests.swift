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

@MainActor
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
        mockService.result = .failure(HFModelCatalogError.unexpectedResponse(statusCode: 500))

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
