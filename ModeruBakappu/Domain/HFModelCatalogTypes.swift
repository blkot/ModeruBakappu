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
