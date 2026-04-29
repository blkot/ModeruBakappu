//
//  ModelRow.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct ModelRow: View {
    let model: DiscoveredModel
    let backupState: ModelBackupState
    let onBackup: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                    if let publisher = model.publisher {
                        Text(publisher)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(model.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Text(model.sizeDescription)
                    Text(model.fileCountDescription)
                    if let lastModified = model.lastModified {
                        Text(lastModified, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let summary = backupState.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(backupStateColor)
                }
            }

            Spacer()

            Button(backupState.buttonTitle, action: onBackup)
                .disabled(!backupState.canTriggerBackup)
        }
        .padding(.vertical, 4)
    }

    private var backupStateColor: Color {
        switch backupState {
        case .destinationConflict, .failed:
            return .red
        case .inProgress:
            return .orange
        case .backedUp:
            return .green
        case .unavailable, .ready:
            return .secondary
        }
    }
}
