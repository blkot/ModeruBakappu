//
//  AppState.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

enum BookmarkKey: String, CaseIterable {
    case lmStudioModels
    case omlxModels
    case backupRoot
}

enum ModelProvider: String, Equatable, Codable {
    case lmStudio = "lm_studio"
    case omlx = "omlx"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .lmStudio:
            return "LM Studio"
        case .omlx:
            return "oMLX"
        case .custom:
            return "Custom Source"
        }
    }

    var backupDirectoryName: String {
        switch self {
        case .lmStudio:
            return "lm-studio"
        case .omlx:
            return "omlx"
        case .custom:
            return "custom"
        }
    }

    var bookmarkKey: BookmarkKey? {
        switch self {
        case .lmStudio:
            return .lmStudioModels
        case .omlx:
            return .omlxModels
        case .custom:
            return nil
        }
    }
}

struct DetectedSourceConfiguration: Equatable {
    let provider: ModelProvider
    let folderURL: URL
}

struct ModelSourceConfiguration: Identifiable, Equatable {
    let provider: ModelProvider
    var folderURL: URL?
    var accessState: SourceAccessState
    var discoveryState: LMStudioDiscoveryState
    var models: [DiscoveredModel]
    var bookmarkIsStale: Bool

    var id: String { provider.rawValue }
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
            return "Choose a models folder before discovery begins."
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
    case permissionDenied

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
        case .permissionDenied:
            return "Permission Denied"
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
        case .permissionDenied:
            return "The selected backup folder exists, but the app does not currently have write permission."
        }
    }
}

struct BackupDriveSpaceInfo: Equatable {
    let volumeName: String?
    let volumePath: String
    let availableBytes: Int64
    let totalBytes: Int64

    var usedBytes: Int64 {
        max(totalBytes - availableBytes, 0)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var availableDescription: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }

    var totalDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var usedDescription: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }

    var usedPercentageDescription: String {
        usedFraction.formatted(.percent.precision(.fractionLength(0)))
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
            return "Source discovery is unavailable until the models folder is ready."
        case .scanning:
            return "Scanning the selected models folder."
        case let .ready(count):
            return "Discovered \(count) models from the configured folder."
        case .empty:
            return "No models were found in the configured folder."
        case let .failed(message):
            return message
        }
    }
}

enum ModelBackupState: Equatable {
    case unavailable
    case ready
    case inProgress
    case backedUp(BackupRecord)
    case failed(String)

    var buttonTitle: String {
        switch self {
        case .unavailable, .ready:
            return "Backup"
        case .inProgress:
            return "Backing Up…"
        case .backedUp:
            return "Backed Up"
        case .failed:
            return "Retry Backup"
        }
    }

    var summary: String? {
        switch self {
        case .unavailable:
            return "Backup remains unavailable until the backup root is online."
        case .ready:
            return nil
        case .inProgress:
            return "Copying and verifying backup contents."
        case let .backedUp(record):
            return "Verified backup created \(record.backedUpAt.formatted(date: .abbreviated, time: .shortened))."
        case let .failed(message):
            return message
        }
    }

    var canTriggerBackup: Bool {
        switch self {
        case .ready, .failed:
            return true
        case .unavailable, .inProgress, .backedUp:
            return false
        }
    }

    var backupRecord: BackupRecord? {
        switch self {
        case let .backedUp(record):
            return record
        case .unavailable, .ready, .inProgress, .failed:
            return nil
        }
    }
}

enum ProviderReadinessState: Equatable {
    case ready
    case notReady(String)
    case unknown(String)

    var title: String {
        switch self {
        case .ready:
            return "Provider Ready"
        case .notReady:
            return "Provider Not Ready"
        case .unknown:
            return "Provider Unknown"
        }
    }

    var summary: String? {
        switch self {
        case .ready:
            return nil
        case let .notReady(message), let .unknown(message):
            return message
        }
    }
}

enum ModelLifecycleState: Equatable {
    case localOnly
    case backedUp(BackupRecord)
    case backupUnavailable
    case backingUp
    case backupFailed(String)
    case archiving
    case archiveFailed(String)
    case archived(BackupRecord)
    case restoring
    case restoreFailed(String)
    case restorable(BackupRecord)
    case missingBackupDrive(BackupRecord)
    case restoreConflict(String)
    case providerNotReady(String)
    case unknown(String)

    var title: String {
        switch self {
        case .localOnly:
            return "Local Only"
        case .backedUp:
            return "Backed Up"
        case .backupUnavailable:
            return "Backup Unavailable"
        case .backingUp:
            return "Backing Up"
        case .backupFailed:
            return "Backup Failed"
        case .archiving:
            return "Archiving"
        case .archiveFailed:
            return "Archive Failed"
        case .archived:
            return "Archived"
        case .restoring:
            return "Restoring"
        case .restoreFailed:
            return "Restore Failed"
        case .restorable:
            return "Restorable"
        case .missingBackupDrive:
            return "Drive Offline"
        case .restoreConflict:
            return "Restore Conflict"
        case .providerNotReady:
            return "Provider Not Ready"
        case .unknown:
            return "Unknown"
        }
    }

    var summary: String {
        switch self {
        case .localOnly:
            return "Stored only on this Mac."
        case let .backedUp(record):
            return "Verified backup at \(record.backupRelativePath)."
        case .backupUnavailable:
            return "Backup actions require an online backup drive."
        case .backingUp:
            return "Copying and verifying backup contents."
        case let .backupFailed(message):
            return message
        case .archiving:
            return "Copying, verifying, and preparing local removal."
        case let .archiveFailed(message):
            return message
        case let .archived(record):
            return "Local data removed; backup is at \(record.backupRelativePath)."
        case .restoring:
            return "Copying and verifying local contents."
        case let .restoreFailed(message):
            return message
        case let .restorable(record):
            return "Can restore from \(record.backupRelativePath)."
        case let .missingBackupDrive(record):
            return "Backup record exists at \(record.backupRelativePath), but the drive is offline."
        case let .restoreConflict(message), let .providerNotReady(message), let .unknown(message):
            return message
        }
    }
}

struct ModelLifecycleStatus: Equatable {
    let state: ModelLifecycleState
    let providerReadiness: ProviderReadinessState
    let backupState: ModelBackupState

    var canTriggerArchive: Bool {
        switch state {
        case .localOnly, .backedUp, .backupFailed, .archiveFailed:
            return backupState != .inProgress
        case .backupUnavailable, .backingUp, .archiving, .archived, .restoring, .restoreFailed, .restorable, .missingBackupDrive, .restoreConflict, .providerNotReady, .unknown:
            return false
        }
    }

    var canTriggerRestore: Bool {
        switch state {
        case .restorable, .restoreFailed:
            return true
        case .localOnly, .backedUp, .backupUnavailable, .backingUp, .backupFailed, .archiving, .archiveFailed, .archived, .restoring, .missingBackupDrive, .restoreConflict, .providerNotReady, .unknown:
            return false
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

struct BackupRecord: Codable, Equatable, Identifiable {
    let modelID: String
    let source: String
    let displayName: String
    let relativePath: String
    let backupRelativePath: String
    let sizeBytes: Int64
    let fileCount: Int
    let backedUpAt: Date
    let localState: ModelLocalState?
    let archivedAt: Date?
    let restoredAt: Date?

    var id: String { modelID }

    var effectiveLocalState: ModelLocalState {
        localState ?? .present
    }
}

enum ModelLocalState: String, Codable, Equatable {
    case present
    case archived
}

struct BackupRootMarker: Codable, Equatable {
    let schemaVersion: Int
    let backupRootID: UUID
    let appName: String
    let createdAt: Date
}
