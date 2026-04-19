//
//  AppState.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

enum PermissionState: Equatable {
    case unknown
    case ready
    case missing
}

enum BackupDriveState: Equatable {
    case unknown
    case online
    case offline
}
