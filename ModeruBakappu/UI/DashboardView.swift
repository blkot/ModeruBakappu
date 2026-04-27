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
                        onSelect: { selectedProvider = configuration.provider },
                        onChooseFolder: {
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
                    lifecycleStatus: { appModel.lifecycleStatus(for: $0) },
                    onBackup: { appModel.backup(model: $0) }
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
                        .foregroundStyle(.primary)
                    Text(configuration.discoveryState.title)
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
            }

            Text(configuration.folderURL?.lastPathComponent ?? "No folder selected")
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
                Button("Refresh Scan", action: onRefresh)
                    .disabled(configuration.discoveryState == .scanning || configuration.discoveryState == .unavailable)
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
    let lifecycleStatus: (DiscoveredModel) -> ModelLifecycleStatus
    let onBackup: (DiscoveredModel) -> Void

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
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Divider()

            switch configuration.discoveryState {
            case .idle, .scanning, .unavailable, .empty:
                EmptyModelState(message: configuration.discoveryState.summary)
            case let .failed(message):
                EmptyModelState(message: message)
            case .ready:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(configuration.models) { model in
                            ProviderModelRow(
                                model: model,
                                provider: configuration.provider,
                                lifecycleStatus: lifecycleStatus(model),
                                onBackup: { onBackup(model) }
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

            Button(lifecycleStatus.backupState.buttonTitle, action: onBackup)
                .disabled(!lifecycleStatus.backupState.canTriggerBackup)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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
        }
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

    private var color: Color {
        switch status.state {
        case .backupFailed, .restoreConflict, .providerNotReady:
            return .red
        case .backingUp:
            return .orange
        case .backedUp, .restorable:
            return .green
        case .archived:
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
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
            )
    }

    private var initials: String {
        switch provider {
        case .lmStudio:
            return "LM"
        case .omlx:
            return "OX"
        case .custom:
            return "CS"
        }
    }

    private var color: Color {
        switch provider {
        case .lmStudio:
            return .blue
        case .omlx:
            return .purple
        case .custom:
            return .gray
        }
    }
}
