//
//  HFModelCatalogService.swift
//  ModeruBakappu
//

import Foundation

// MARK: - Error

enum HFModelCatalogError: Error {
    case invalidURL
    case networkError(Error)
    case unexpectedResponse(statusCode: Int)
    case decodingError(Error)
}

// MARK: - Protocol

protocol HFModelCatalogServiceProtocol {
    func searchModels(filter: HFSearchFilter, page: Int, endpoint: URL) async throws -> (items: [HFModelCatalogItem], hasMore: Bool)
}

// MARK: - Raw API Types

private struct RawModelSibling: Decodable {
    let rfilename: String
    let size: Int64?
}

private struct RawSafetensors: Decodable {
    let parameters: [String: [String]]?
}

private struct RawModelItem: Decodable {
    let id: String
    let author: String?
    let modelId: String?
    let pipelineTag: String?
    let tags: [String]?
    let siblings: [RawModelSibling]?
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let safetensors: RawSafetensors?
}

// MARK: - Domain Conversion

private extension HFModelCatalogItem {
    init(raw: RawModelItem) {
        let idComponents = raw.id.split(separator: "/", maxSplits: 1)
        if idComponents.count == 2 {
            author = String(idComponents[0])
            modelName = String(idComponents[1])
        } else {
            author = raw.author ?? "unknown"
            modelName = raw.id
        }

        let date: Date
        if let lastModifiedStr = raw.lastModified {
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = withFractional.date(from: lastModifiedStr) {
                date = parsed
            } else if let parsed = ISO8601DateFormatter().date(from: lastModifiedStr) {
                date = parsed
            } else {
                date = .distantPast
            }
        } else {
            date = .distantPast
        }

        id = raw.id
        pipelineTag = raw.pipelineTag
        tags = raw.tags ?? []
        files = (raw.siblings ?? []).map { HFModelFile(filename: $0.rfilename, sizeBytes: $0.size ?? 0) }
        downloads = raw.downloads ?? 0
        likes = raw.likes ?? 0
        lastModified = date
        safetensorsAvailable = raw.safetensors != nil
    }
}

// MARK: - Service Implementation

final class HFModelCatalogService: HFModelCatalogServiceProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func searchModels(filter: HFSearchFilter, page: Int, endpoint: URL) async throws -> (items: [HFModelCatalogItem], hasMore: Bool) {
        var components = URLComponents(
            url: endpoint.appendingPathComponent("models"),
            resolvingAgainstBaseURL: false
        )

        guard var components else {
            throw HFModelCatalogError.invalidURL
        }

        var queryItems: [URLQueryItem] = []

        if !filter.searchQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: filter.searchQuery))
        }

        if let formatFilter = filter.formatFilter {
            queryItems.append(URLQueryItem(name: "filter", value: formatFilter.rawValue))
        }

        queryItems.append(URLQueryItem(name: "sort", value: filter.sortField.rawValue))
        queryItems.append(URLQueryItem(name: "direction", value: filter.ascending ? "1" : "-1"))

        let limit = 20
        let offset = page * limit
        queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
        queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))

        components.queryItems = queryItems

        guard let url = components.url else {
            throw HFModelCatalogError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw HFModelCatalogError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HFModelCatalogError.unexpectedResponse(statusCode: -1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HFModelCatalogError.unexpectedResponse(statusCode: httpResponse.statusCode)
        }

        let rawItems: [RawModelItem]
        do {
            rawItems = try decoder.decode([RawModelItem].self, from: data)
        } catch {
            throw HFModelCatalogError.decodingError(error)
        }

        let items = rawItems.map { HFModelCatalogItem(raw: $0) }
        let hasMore = rawItems.count == limit

        return (items, hasMore)
    }
}
