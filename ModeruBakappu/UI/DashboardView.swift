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
                    Text("\(appModel.configuredSourceCount) sources configured, \(appModel.discoveredModelCount) models discovered. Backup actions remain gated on drive availability.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                ForEach(appModel.sourceConfigurations) { configuration in
                    FolderStatusCard(
                        title: "\(configuration.provider.displayName) Models Folder",
                        path: configuration.folderURL?.path,
                        stateTitle: configuration.accessState.title,
                        summary: configuration.accessState.summary,
                        accentColor: color(for: configuration.accessState),
                        primaryActionTitle: configuration.folderURL == nil ? "Choose Folder" : "Change Folder",
                        onPrimaryAction: { appModel.selectSourceFolder(for: configuration.provider) },
                        secondaryActionTitle: "Revalidate",
                        onSecondaryAction: { appModel.refreshStatuses() }
                    )
                }

                FolderStatusCard(
                    title: "Backup Root",
                    path: appModel.backupFolderURL?.path,
                    stateTitle: appModel.backupDriveState.title,
                    summary: appModel.backupDriveSummary,
                    accentColor: color(for: appModel.backupDriveState),
                    primaryActionTitle: "Change Backup Root",
                    onPrimaryAction: { appModel.selectBackupFolder() },
                    secondaryActionTitle: "Revalidate",
                    onSecondaryAction: { appModel.refreshStatuses() }
                )

                ForEach(appModel.sourceConfigurations) { configuration in
                    ModelsPanel(
                        sourceDisplayName: configuration.provider.displayName,
                        discoveryState: configuration.discoveryState,
                        models: configuration.models,
                        backupState: { model in
                            appModel.backupState(for: model)
                        },
                        onBackup: { model in
                            appModel.backup(model: model)
                        },
                        onRefresh: { appModel.refreshModelDiscovery() }
                    )
                }
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
        case .permissionDenied:
            return .red
        case .notConfigured, .offline:
            return .secondary
        }
    }
}
