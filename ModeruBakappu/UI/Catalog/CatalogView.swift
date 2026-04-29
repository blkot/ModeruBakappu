//
//  CatalogView.swift
//  ModeruBakappu
//

import SwiftUI

struct CatalogView: View {
    @ObservedObject var viewModel: CatalogViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                modelList
                    .frame(width: 340)

                Divider()

                detailPanel
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .alert("HF Endpoint Detected", isPresented: shellEndpointBinding) {
            Button("Use Detected") { viewModel.adoptShellEndpoint() }
            Button("Ignore") { viewModel.dismissShellEndpointPrompt() }
        } message: {
            Text("Found \"\(viewModel.shellEndpointCandidate ?? "")\" in your shell config. Use this as the Hugging Face API endpoint?")
        }
        .alert("Search Error", isPresented: errorBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: searchBinding)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        viewModel.search()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            Picker("Format", selection: formatBinding) {
                Text("All Formats").tag(HFModelFormat?.none)
                Text("GGUF").tag(HFModelFormat?.some(.gguf))
                Text("MLX").tag(HFModelFormat?.some(.mlx))
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("Sort", selection: sortBinding) {
                ForEach(HFModelSortField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Button {
                viewModel.search()
            } label: {
                Text("Search")
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var modelList: some View {
        Group {
            if viewModel.items.isEmpty {
                VStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView("Searching...")
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Search Hugging Face models")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.items) { item in
                            CatalogModelRow(
                                item: item,
                                isSelected: viewModel.selectedItem?.id == item.id
                            )
                            .onTapGesture {
                                viewModel.selectItem(item)
                            }
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentItem: item)
                            }

                            Divider()
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedItem = viewModel.selectedItem {
            CatalogModelDetail(item: selectedItem)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.leadinghalf.inset.filled")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select a model to see details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bindings

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.searchQuery = $0 }
        )
    }

    private var formatBinding: Binding<HFModelFormat?> {
        Binding(
            get: { viewModel.formatFilter },
            set: { viewModel.formatFilter = $0 }
        )
    }

    private var sortBinding: Binding<HFModelSortField> {
        Binding(
            get: { viewModel.sortField },
            set: { viewModel.sortField = $0 }
        )
    }

    private var shellEndpointBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showShellEndpointPrompt },
            set: { _ in }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }
}

private extension HFModelSortField {
    var displayName: String {
        switch self {
        case .downloads: return "Downloads"
        case .likes: return "Likes"
        case .lastModified: return "Last Modified"
        case .trending: return "Trending"
        }
    }
}
