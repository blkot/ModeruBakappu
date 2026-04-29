//
//  CatalogModelDetail.swift
//  ModeruBakappu
//

import SwiftUI

struct CatalogModelDetail: View {
    let item: HFModelCatalogItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.modelName)
                        .font(.title2.weight(.semibold))
                    Text(item.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 16) {
                    StatLabel(title: "Downloads", value: item.formattedDownloads)
                    StatLabel(title: "Likes", value: item.formattedLikes)
                    StatLabel(title: "Updated", value: item.lastModified.formatted(date: .abbreviated, time: .omitted))
                }

                if let pipelineTag = item.pipelineTag {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pipeline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(pipelineTag)
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                if !item.files.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Files")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 6) {
                            ForEach(item.files) { file in
                                FileRow(file: file)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }
}

private struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FileRow: View {
    let file: HFModelFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.sizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Download") {
                // Deferred to next iteration
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
            .help("Download to the backup drive. Requires the backup drive to be online and writable.")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}
