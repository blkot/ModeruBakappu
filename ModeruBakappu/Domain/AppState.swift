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

struct ResolvedBookmark: Equatable {
    let url: URL
    let isStale: Bool
}
