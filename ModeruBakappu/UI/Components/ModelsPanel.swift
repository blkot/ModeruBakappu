//
//  ModelsPanel.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct ModelsPanel: View {
    let discoveryState: LMStudioDiscoveryState
    let models: [DiscoveredModel]
    let backupState: (DiscoveredModel) -> ModelBackupState
    let onBackup: (DiscoveredModel) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LM Studio Models")
                        .font(.headline)
                    Text(discoveryState.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh Scan", action: onRefresh)
                    .disabled(discoveryState == .scanning || discoveryState == .unavailable)
            }

            switch discoveryState {
            case .idle, .scanning, .unavailable, .empty:
                Text(discoveryState.summary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            case .ready:
                VStack(spacing: 0) {
                    ForEach(models) { model in
                        ModelRow(
                            model: model,
                            backupState: backupState(model),
                            onBackup: { onBackup(model) }
                        )
                        if model.id != models.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}
