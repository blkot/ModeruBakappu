//
//  AppState.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

enum BookmarkKey: String, CaseIterable {
    case lmStudioModels
    case backupRoot
}

enum SourceAccessState: Equatable {
    case notConfigured
    case ready
    case staleBookmark
    case inaccessible

    var title: String {
        switch self {
        case .notConfigured:
            return "Not Configured"
        case .ready:
            return "Ready"
        case .staleBookmark:
            return "Needs Reselection"
        case .inaccessible:
            return "Unavailable"
        }
    }

    var summary: String {
        switch self {
        case .notConfigured:
            return "Choose the LM Studio models folder before discovery begins."
        case .ready:
            return "The selected source folder can be accessed."
        case .staleBookmark:
            return "The saved folder reference is stale and must be selected again."
        case .inaccessible:
            return "The selected folder could not be read."
        }
    }
}

enum BackupDriveState: Equatable {
    case notConfigured
    case online
    case offline
    case staleBookmark
    case readOnly

    var title: String {
        switch self {
        case .notConfigured:
            return "Not Configured"
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .staleBookmark:
            return "Needs Reselection"
        case .readOnly:
            return "Read Only"
        }
    }

    var summary: String {
        switch self {
        case .notConfigured:
            return "Choose a backup root on your external drive."
        case .online:
            return "The selected backup folder is reachable and writable."
        case .offline:
            return "The selected backup folder is missing or the drive is disconnected."
        case .staleBookmark:
            return "The saved backup folder reference is stale and must be selected again."
        case .readOnly:
            return "The selected backup folder can be read but not written."
        }
    }
}

enum LMStudioDiscoveryState: Equatable {
    case idle
    case unavailable
    case scanning
    case ready(count: Int)
    case empty
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "Not Started"
        case .unavailable:
            return "Unavailable"
        case .scanning:
            return "Scanning"
        case let .ready(count):
            return "\(count) Models"
        case .empty:
            return "No Models"
        case .failed:
            return "Scan Failed"
        }
    }

    var summary: String {
        switch self {
        case .idle:
            return "Discovery has not run yet."
        case .unavailable:
            return "LM Studio discovery is unavailable until the source folder is ready."
        case .scanning:
            return "Scanning the selected LM Studio folder."
        case let .ready(count):
            return "Discovered \(count) LM Studio models from the configured folder."
        case .empty:
            return "No LM Studio models were found in the configured folder."
        case let .failed(message):
            return message
        }
    }
}

struct ResolvedBookmark: Equatable {
    let url: URL
    let isStale: Bool
}

struct DiscoveredModel: Identifiable, Equatable {
    let id: String
    let source: String
    let publisher: String?
    let displayName: String
    let folderURL: URL
    let relativePath: String
    let sizeBytes: Int64
    let fileCount: Int
    let lastModified: Date?

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var fileCountDescription: String {
        fileCount == 1 ? "1 file" : "\(fileCount) files"
    }
}
