//
//  SettingsView.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Source Access") {
                ForEach(appModel.sourceConfigurations) { configuration in
                    LabeledContent("\(configuration.provider.displayName) Folder") {
                        Text(configuration.folderURL?.path ?? "Not configured")
                            .foregroundStyle(configuration.folderURL == nil ? .secondary : .primary)
                    }

                    LabeledContent("\(configuration.provider.displayName) Status") {
                        Text(configuration.accessState.title)
                    }

                    HStack {
                        Button("Choose \(configuration.provider.displayName) Folder") {
                            appModel.selectSourceFolder(for: configuration.provider)
                        }
                    }
                }
            }

            Section("Backup Destination") {
                LabeledContent("Backup Root") {
                    Text(appModel.backupFolderURL?.path ?? "Not configured")
                        .foregroundStyle(appModel.backupFolderURL == nil ? .secondary : .primary)
                }

                LabeledContent("Drive Status") {
                    Text(appModel.backupDriveState.title)
                }

                HStack {
                    Button("Choose Backup Root") {
                        appModel.selectBackupFolder()
                    }
                    Button("Revalidate") {
                        appModel.refreshStatuses()
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 680)
    }
}
