//
//  DashboardView.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedProvider: ModelProvider = .lmStudio
    @State private var pendingActionSheet: ModelActionSheet?

    private var selectedConfiguration: ModelSourceConfiguration? {
        appModel.sourceConfigurations.first { $0.provider == selectedProvider }
            ?? appModel.sourceConfigurations.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                providerSidebar
                    .frame(width: 260)
                    .background(Color(nsColor: .underPageBackgroundColor))

                Divider()

                selectedProviderContent
            }
        }
        .onAppear {
            if !appModel.sourceConfigurations.contains(where: { $0.provider == selectedProvider }),
               let firstProvider = appModel.sourceConfigurations.first?.provider {
                selectedProvider = firstProvider
            }
        }
        .sheet(item: $pendingActionSheet) { sheet in
            switch sheet {
            case let .archive(request):
                ArchiveConfirmationSheet(
                    provider: request.provider,
                    model: request.model,
                    onCancel: { pendingActionSheet = nil },
                    onArchive: {
                        pendingActionSheet = nil
                        appModel.archive(model: request.model)
                    }
                )
            case let .restore(request):
                RestoreConfirmationSheet(
                    provider: request.provider,
                    model: request.model,
                    onCancel: { pendingActionSheet = nil },
                    onRestore: {
                        pendingActionSheet = nil
                        appModel.restore(model: request.model)
                    }
                )
            case let .deleteLocal(request):
                DeleteLocalConfirmationSheet(
                    provider: request.provider,
                    model: request.model,
                    onCancel: { pendingActionSheet = nil },
                    onDelete: {
                        pendingActionSheet = nil
                        appModel.deleteLocalCopy(model: request.model)
                    }
                )
            case let .deleteBackup(request):
                DeleteBackupConfirmationSheet(
                    provider: request.provider,
                    model: request.model,
                    backupRelativePath: request.backupRelativePath ?? request.model.relativePath,
                    requiresTypedConfirmation: request.requiresTypedConfirmation,
                    onCancel: { pendingActionSheet = nil },
                    onDelete: {
                        pendingActionSheet = nil
                        appModel.deleteBackup(model: request.model)
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ModeruBakappu")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("\(appModel.configuredSourceCount) sources configured, \(appModel.discoveredModelCount) models discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            topBanners
                .frame(maxWidth: 680)

            Button {
                appModel.refreshStatuses()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
    }

    private var topBanners: some View {
        HStack(alignment: .center, spacing: 10) {
            DriveStatusBanner(
                title: "Backup Drive",
                iconName: "externaldrive",
                path: appModel.backupFolderURL?.path,
                statusTitle: appModel.backupDriveState.title,
                spaceInfo: appModel.backupDriveSpaceInfo,
                unavailableSpaceText: appModel.backupDriveState == .notConfigured ? "No backup root" : "Space unavailable",
                accentColor: color(for: appModel.backupDriveState),
                onChange: { appModel.selectBackupFolder() },
                onRevalidate: { appModel.refreshStatuses() }
            )

            DriveStatusBanner(
                title: "Mac Drive",
                iconName: "internaldrive",
                path: appModel.mainDriveSpaceInfo?.volumePath,
                statusTitle: appModel.mainDriveSpaceInfo == nil ? "Unavailable" : "Online",
                spaceInfo: appModel.mainDriveSpaceInfo,
                unavailableSpaceText: "Space unavailable",
                accentColor: appModel.mainDriveSpaceInfo == nil ? .secondary : .blue,
                onChange: nil,
                onRevalidate: { appModel.refreshStatuses() }
            )
        }
    }

    private var providerSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            VStack(spacing: 8) {
                ForEach(appModel.sourceConfigurations) { configuration in
                    ProviderSidebarRow(
                        configuration: configuration,
                        isSelected: selectedProvider == configuration.provider,
                        accessColor: color(for: configuration.accessState),
                        onSelect: {
                            guard configuration.provider.isEnabled else { return }
                            selectedProvider = configuration.provider
                        },
                        onChooseFolder: {
                            guard configuration.provider.isEnabled else { return }
                            selectedProvider = configuration.provider
                            appModel.selectSourceFolder(for: configuration.provider)
                        }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
    }

    @ViewBuilder
    private var selectedProviderContent: some View {
        if let configuration = selectedConfiguration {
            VStack(alignment: .leading, spacing: 0) {
                ProviderDetailHeader(
                    configuration: configuration,
                    accessColor: color(for: configuration.accessState),
                    backupRootPath: appModel.backupFolderURL?.path,
                    onChooseFolder: { appModel.selectSourceFolder(for: configuration.provider) },
                    onRefresh: { appModel.refreshModelDiscovery() }
                )
                .padding(24)

                Divider()

                ModelListView(
                    configuration: configuration,
                    models: appModel.displayModels(for: configuration),
                    lifecycleStatus: { appModel.lifecycleStatus(for: $0) },
                    onBackup: { appModel.backup(model: $0) },
                    onArchive: { pendingActionSheet = .archive(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onRestore: { pendingActionSheet = .restore(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onDeleteLocal: { pendingActionSheet = .deleteLocal(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onDeleteBackup: { model in
                        let record = appModel.backupRecords[model.id]
                        pendingActionSheet = .deleteBackup(
                            ModelActionRequest(
                                provider: configuration.provider,
                                model: model,
                                backupRelativePath: record?.backupRelativePath,
                                requiresTypedConfirmation: record?.effectiveLocalState == .archived
                            )
                        )
                    },
                    onRevealLocal: { appModel.revealLocalModel($0) },
                    onRevealBackup: { appModel.revealBackup(for: $0) }
                )
            }
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

private struct ModelActionRequest: Identifiable {
    let provider: ModelProvider
    let model: DiscoveredModel
    var backupRelativePath: String?
    var requiresTypedConfirmation = false

    var id: String {
        "\(provider.rawValue):\(model.id):\(requiresTypedConfirmation)"
    }
}

private enum ModelActionSheet: Identifiable {
    case archive(ModelActionRequest)
    case restore(ModelActionRequest)
    case deleteLocal(ModelActionRequest)
    case deleteBackup(ModelActionRequest)

    var id: String {
        switch self {
        case let .archive(request):
            return "archive:\(request.id)"
        case let .restore(request):
            return "restore:\(request.id)"
        case let .deleteLocal(request):
            return "delete-local:\(request.id)"
        case let .deleteBackup(request):
            return "delete-backup:\(request.id)"
        }
    }
}

private struct ArchiveConfirmationSheet: View {
    let provider: ModelProvider
    let model: DiscoveredModel
    let onCancel: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Archive Model?")
                        .font(.title3.weight(.semibold))
                    Text("This will free space on this Mac after backup verification.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ModelActionInfoFrame(provider: provider, model: model)

            Text("ModeruBakappu will copy and verify this model on the backup drive, then remove the local model folder from this Mac. Use Back Up when you want a duplicate; use Archive when you want to free space on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Archive", role: .destructive, action: onArchive)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RestoreConfirmationSheet: View {
    let provider: ModelProvider
    let model: DiscoveredModel
    let onCancel: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Restore Model?")
                        .font(.title3.weight(.semibold))
                    Text("This will copy the archived model back to this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ModelActionInfoFrame(provider: provider, model: model)

            Text("ModeruBakappu will copy and verify this model from the backup drive back into the provider's model folder. The archived backup remains on the backup drive.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Restore", action: onRestore)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DeleteLocalConfirmationSheet: View {
    let provider: ModelProvider
    let model: DiscoveredModel
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                DestructiveActionIcon(systemName: "trash")

                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete Local Model?")
                        .font(.title3.weight(.semibold))
                    Text("The verified backup remains available on the backup drive.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ModelActionInfoFrame(provider: provider, model: model)

            Text("This removes the model files used by the provider runtime on this Mac. The verified backup remains on the backup drive and can be restored later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete Local Model", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DeleteBackupConfirmationSheet: View {
    let provider: ModelProvider
    let model: DiscoveredModel
    let backupRelativePath: String
    let requiresTypedConfirmation: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var confirmationText = ""

    private var canDelete: Bool {
        !requiresTypedConfirmation || confirmationText == "DELETE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                DestructiveActionIcon(systemName: "externaldrive.badge.minus")

                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete Backup?")
                        .font(.title3.weight(.semibold))
                    Text(requiresTypedConfirmation ? "This may remove the only known copy." : "The local model remains on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ModelActionInfoFrame(
                provider: provider,
                model: model,
                pathTitle: "Backup Path",
                pathValue: backupRelativePath
            )

            Text("This removes the backup copy from the selected backup drive. This cannot be restored unless another copy exists.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if requiresTypedConfirmation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type DELETE to confirm.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("DELETE", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete Backup", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canDelete)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

}

private struct DestructiveActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ModelActionInfoFrame: View {
    let provider: ModelProvider
    let model: DiscoveredModel
    var pathTitle = "Path"
    var pathValue: String?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                Text("Provider")
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                    .fontWeight(.semibold)
            }

            GridRow {
                Text("Model")
                    .foregroundStyle(.secondary)
                Text(model.displayName)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            GridRow {
                Text(pathTitle)
                    .foregroundStyle(.secondary)
                Text(pathValue ?? model.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.24))
            )
    }
}

private struct DriveStatusBanner: View {
    let title: String
    let iconName: String
    let path: String?
    let statusTitle: String
    let spaceInfo: BackupDriveSpaceInfo?
    let unavailableSpaceText: String
    let accentColor: Color
    let onChange: (() -> Void)?
    let onRevalidate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundStyle(accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12), in: Capsule())
                }

                if let spaceInfo {
                    HStack(spacing: 8) {
                        ProgressView(value: spaceInfo.usedFraction)
                            .tint(spaceTint)
                            .frame(width: 80)

                        Text("\(spaceInfo.availableDescription) free")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                } else {
                    Text(unavailableSpaceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                if let onChange {
                    Button(action: onChange) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.link)
                    .help("Change backup root")
                }
                Button(action: onRevalidate) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.link)
                .help("Revalidate")
            }
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .help(path ?? "No folder selected")
    }

    private var spaceTint: Color {
        guard let usedFraction = spaceInfo?.usedFraction else { return .secondary }
        if usedFraction > 0.9 {
            return .red
        }
        if usedFraction > 0.75 {
            return .orange
        }
        return .green
    }
}

private struct ProviderSidebarRow: View {
    let configuration: ModelSourceConfiguration
    let isSelected: Bool
    let accessColor: Color
    let onSelect: () -> Void
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ProviderBadge(provider: configuration.provider)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.provider.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(configuration.provider.isEnabled ? .primary : .secondary)
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(accessColor)
                    .frame(width: 7, height: 7)
                Text(configuration.accessState.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Folder", action: onChooseFolder)
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(!configuration.provider.isEnabled)
            }

            Text(folderSummary)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .opacity(configuration.provider.isEnabled ? 1 : 0.48)
        .help(configuration.provider.disabledReason ?? configuration.accessState.summary)
    }

    private var statusTitle: String {
        configuration.provider.disabledReason ?? configuration.discoveryState.title
    }

    private var folderSummary: String {
        if let disabledReason = configuration.provider.disabledReason {
            return disabledReason
        }
        return configuration.folderURL?.lastPathComponent ?? "No folder selected"
    }
}

private struct ProviderDetailHeader: View {
    let configuration: ModelSourceConfiguration
    let accessColor: Color
    let backupRootPath: String?
    let onChooseFolder: () -> Void
    let onRefresh: () -> Void

    var providerBackupPath: String {
        guard let backupRootPath else {
            return "Backup root not configured"
        }
        return "\(backupRootPath)/\(configuration.provider.backupDirectoryName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 12) {
                    ProviderBadge(provider: configuration.provider)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.provider.displayName)
                            .font(.title2.weight(.semibold))
                        Text(configuration.accessState.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Choose Folder", action: onChooseFolder)
                    .disabled(!configuration.provider.isEnabled)
                Button("Refresh Scan", action: onRefresh)
                    .disabled(!configuration.provider.isEnabled || configuration.discoveryState == .scanning || configuration.discoveryState == .unavailable)
            }

            HStack(spacing: 12) {
                PathSummary(
                    title: "Model Folder",
                    value: configuration.folderURL?.path ?? "Not configured",
                    color: accessColor
                )
                PathSummary(
                    title: "Backup Namespace",
                    value: providerBackupPath,
                    color: .blue
                )
            }
        }
    }
}

private struct ModelListView: View {
    let configuration: ModelSourceConfiguration
    let models: [DiscoveredModel]
    let lifecycleStatus: (DiscoveredModel) -> ModelLifecycleStatus
    let onBackup: (DiscoveredModel) -> Void
    let onArchive: (DiscoveredModel) -> Void
    let onRestore: (DiscoveredModel) -> Void
    let onDeleteLocal: (DiscoveredModel) -> Void
    let onDeleteBackup: (DiscoveredModel) -> Void
    let onRevealLocal: (DiscoveredModel) -> Void
    let onRevealBackup: (DiscoveredModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Local")
                    .frame(width: 150, alignment: .leading)
                Text("Lifecycle")
                    .frame(width: 210, alignment: .leading)
                Text("Action")
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Divider()

            if models.isEmpty {
                switch configuration.discoveryState {
                case .idle, .scanning, .unavailable, .empty:
                    EmptyModelState(message: configuration.discoveryState.summary)
                case let .failed(message):
                    EmptyModelState(message: message)
                case .ready:
                    EmptyModelState(message: configuration.discoveryState.summary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(models) { model in
                            ProviderModelRow(
                                model: model,
                                provider: configuration.provider,
                                lifecycleStatus: lifecycleStatus(model),
                                onBackup: { onBackup(model) },
                                onArchive: { onArchive(model) },
                                onRestore: { onRestore(model) },
                                onDeleteLocal: { onDeleteLocal(model) },
                                onDeleteBackup: { onDeleteBackup(model) },
                                onRevealLocal: { onRevealLocal(model) },
                                onRevealBackup: { onRevealBackup(model) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct ProviderModelRow: View {
    let model: DiscoveredModel
    let provider: ModelProvider
    let lifecycleStatus: ModelLifecycleStatus
    let onBackup: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDeleteLocal: () -> Void
    let onDeleteBackup: () -> Void
    let onRevealLocal: () -> Void
    let onRevealBackup: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let publisher = model.publisher {
                        Text(publisher)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(model.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.sizeDescription)
                Text(model.fileCountDescription)
                if let lastModified = model.lastModified {
                    Text(lastModified, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .leading)

            LifecycleStatusSummary(provider: provider, status: lifecycleStatus)
                .frame(width: 210, alignment: .leading)

            ModelActionMenu(
                status: lifecycleStatus,
                onBackup: onBackup,
                onArchive: onArchive,
                onRestore: onRestore,
                onDeleteLocal: onDeleteLocal,
                onDeleteBackup: onDeleteBackup,
                onRevealLocal: onRevealLocal,
                onRevealBackup: onRevealBackup
            )
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

private struct ModelActionMenu: View {
    let status: ModelLifecycleStatus
    let onBackup: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDeleteLocal: () -> Void
    let onDeleteBackup: () -> Void
    let onRevealLocal: () -> Void
    let onRevealBackup: () -> Void

    var body: some View {
        Menu {
            Button(status.backupState.buttonTitle, action: onBackup)
                .disabled(!status.backupState.canTriggerBackup)
                .help("Copy this model to the backup drive. The local model stays on this Mac.")

            Divider()

            Button("Reveal Local", action: onRevealLocal)
                .help("Open the local model folder in Finder.")
            Button("Reveal Backup", action: onRevealBackup)
                .disabled(status.backupState.backupRecord == nil)
                .help("Open this model's backup folder in Finder.")

            Divider()

            Button("Archive", action: onArchive)
                .disabled(!status.canTriggerArchive)
                .help("Copy and verify this model on the backup drive, then remove the local model to free space.")
            Button("Restore", action: onRestore)
                .disabled(!status.canTriggerRestore)
                .help("Copy the archived model back to this Mac from the backup drive.")

            Divider()

            Button("Delete Local Model", role: .destructive, action: onDeleteLocal)
                .disabled(!status.canDeleteLocalCopy)
                .help("Remove the provider-usable model files from this Mac. The verified backup remains available.")
            Button("Delete Backup", role: .destructive, action: onDeleteBackup)
                .disabled(!status.canDeleteBackup)
                .help("Remove only the backup copy from the selected backup drive.")
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
    }
}

private struct LifecycleStatusSummary: View {
    let provider: ModelProvider
    let status: ModelLifecycleStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if status.providerReadiness != .ready {
                HStack(spacing: 5) {
                    Image(systemName: providerReadinessIcon)
                        .font(.caption2.weight(.semibold))
                    Text(status.providerReadiness.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(providerReadinessColor)
                .help(providerReadinessHelpText)
            }
        }
        .help(helpText)
    }

    private var title: String {
        status.state.title
    }

    private var subtitle: String {
        switch status.state {
        case .localOnly:
            return "Maps to /\(provider.backupDirectoryName)"
        default:
            return status.state.summary
        }
    }

    private var helpText: String {
        let readinessSuffix: String
        if status.providerReadiness == .ready {
            readinessSuffix = ""
        } else {
            readinessSuffix = "\n\n\(providerReadinessHelpText)"
        }

        switch status.state {
        case .localOnly:
            return "This model exists only on this Mac. Back Up creates a duplicate on the backup drive." + readinessSuffix
        case .backedUp:
            return "A verified backup exists, and the model is still available locally." + readinessSuffix
        case .backupUnavailable:
            return "Backup and archive actions require a reachable writable backup drive." + readinessSuffix
        case .backingUp:
            return "ModeruBakappu is copying and verifying the backup. The local model remains in place." + readinessSuffix
        case let .backupFailed(message):
            return "Backup failed: \(message)" + readinessSuffix
        case .archiving:
            return "ModeruBakappu is ensuring a verified backup exists, then it will remove the local model." + readinessSuffix
        case let .archiveFailed(message):
            return "Archive failed: \(message)" + readinessSuffix
        case .archived:
            return "The local model was removed after backup verification." + readinessSuffix
        case .restoring:
            return "ModeruBakappu is copying the archived model back to this Mac and verifying it." + readinessSuffix
        case let .restoreFailed(message):
            return "Restore failed: \(message)" + readinessSuffix
        case .deletingLocal:
            return "ModeruBakappu is removing the local model folder. The verified backup remains available." + readinessSuffix
        case let .deleteLocalFailed(message):
            return "Delete local model failed: \(message)" + readinessSuffix
        case .deletingBackup:
            return "ModeruBakappu is removing the backup payload from the selected backup drive." + readinessSuffix
        case let .deleteBackupFailed(message):
            return "Delete backup failed: \(message)" + readinessSuffix
        case .restorable:
            return "This model is archived: the local model was removed, and Restore copies it back from the backup drive." + readinessSuffix
        case .missingBackupDrive:
            return "This model is archived, but the backup drive is not currently available." + readinessSuffix
        case let .restoreConflict(message):
            return "Restore conflict: \(message)" + readinessSuffix
        case let .providerNotReady(message):
            return "Provider is not ready: \(message)" + readinessSuffix
        case let .unknown(message):
            return message + readinessSuffix
        }
    }

    private var providerReadinessHelpText: String {
        switch status.providerReadiness {
        case .ready:
            return "Provider readiness is confirmed."
        case let .notReady(message):
            return "Provider is not ready: \(message)"
        case let .unknown(message):
            return "Provider readiness is unknown: \(message)"
        }
    }

    private var providerReadinessIcon: String {
        switch status.providerReadiness {
        case .ready:
            return "checkmark.circle"
        case .notReady:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var providerReadinessColor: Color {
        switch status.providerReadiness {
        case .ready:
            return .green
        case .notReady:
            return .red
        case .unknown:
            return .orange
        }
    }

    private var color: Color {
        switch status.state {
        case .backupFailed, .archiveFailed, .restoreFailed, .deleteLocalFailed, .deleteBackupFailed, .restoreConflict, .providerNotReady:
            return .red
        case .backingUp, .archiving, .restoring, .deletingLocal, .deletingBackup:
            return .orange
        case .backedUp:
            return .green
        case .archived, .restorable:
            return .blue
        case .localOnly, .backupUnavailable, .missingBackupDrive, .unknown:
            return .secondary
        }
    }
}

private struct EmptyModelState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct PathSummary: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ProviderBadge: View {
    let provider: ModelProvider

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)

            if let assetName {
                Image(assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                    .accessibilityLabel(provider.displayName)
            } else {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
    }

    private var iconSize: CGFloat {
        switch provider {
        case .lmStudio:
            return 34
        case .omlx:
            return 23
        case .ollama, .custom:
            return 21
        }
    }

    private var iconCornerRadius: CGFloat {
        switch provider {
        case .lmStudio:
            return 8
        case .omlx, .ollama, .custom:
            return 0
        }
    }

    private var assetName: String? {
        switch provider {
        case .lmStudio:
            return "ProviderLMStudio"
        case .omlx:
            return "ProviderOMLX"
        case .ollama:
            return "ProviderOllama"
        case .custom:
            return nil
        }
    }

    private var initials: String {
        switch provider {
        case .lmStudio:
            return "LM"
        case .omlx:
            return "OX"
        case .ollama:
            return "OL"
        case .custom:
            return "CS"
        }
    }

    private var color: Color {
        switch provider {
        case .lmStudio:
            return .clear
        case .omlx:
            return .white
        case .ollama:
            return .gray
        case .custom:
            return .gray
        }
    }
}
