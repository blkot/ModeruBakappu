//
//  DashboardView.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ModeruBakappu")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Startup configuration is ready. This shell tracks folder access now; discovery and backup actions come next.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                FolderStatusCard(
                    title: "LM Studio Models Folder",
                    path: appModel.lmStudioFolderURL?.path,
                    stateTitle: appModel.lmStudioAccessState.title,
                    summary: appModel.lmStudioAccessState.summary,
                    accentColor: color(for: appModel.lmStudioAccessState),
                    primaryActionTitle: "Change Folder",
                    onPrimaryAction: { appModel.selectLMStudioFolder() },
                    secondaryActionTitle: "Revalidate",
                    onSecondaryAction: { appModel.refreshStatuses() }
                )

                FolderStatusCard(
                    title: "Backup Root",
                    path: appModel.backupFolderURL?.path,
                    stateTitle: appModel.backupDriveState.title,
                    summary: appModel.backupDriveState.summary,
                    accentColor: color(for: appModel.backupDriveState),
                    primaryActionTitle: "Change Backup Root",
                    onPrimaryAction: { appModel.selectBackupFolder() },
                    secondaryActionTitle: "Revalidate",
                    onSecondaryAction: { appModel.refreshStatuses() }
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Next implementation milestone")
                        .font(.headline)
                    Text("Add LM Studio discovery against the configured folder, then gate backup actions on the backup drive state.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
            }
            .padding(32)
        }
    }

    private func color(for state: SourceAccessState) -> Color {
        switch state {
        case .ready:
            return .green
        case .staleBookmark:
            return .orange
        case .notConfigured, .inaccessible:
            return .secondary
        }
    }

    private func color(for state: BackupDriveState) -> Color {
        switch state {
        case .online:
            return .green
        case .staleBookmark:
            return .orange
        case .readOnly:
            return .yellow
        case .notConfigured, .offline:
            return .secondary
        }
    }
}
