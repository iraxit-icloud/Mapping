import SwiftUI

struct MapEditorView: View {
    @StateObject private var vm = MapEditorViewModel()
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                if vm.maps.isEmpty {
                    ContentUnavailableView("No maps yet", systemImage: "map", description: Text("Scan a space and save to see maps here."))
                } else {
                    ForEach(vm.maps) { card in
                        HStack(alignment: .center, spacing: 12) {
                            // Thumbnail (if PNG exists)
                            if let url = card.pngURL, let ui = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.1))
                                    Image(systemName: "map")
                                }
                                .frame(width: 56, height: 56)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                // Map name is the primary action: preview PNG
                                Button {
                                    vm.preview(card)
                                } label: {
                                    Text(card.title.isEmpty ? "Untitled" : card.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)

                                Text(vm.formattedDate(card.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Right-side minimal icons: Share & Edit
                            HStack(spacing: 12) {
                                Button {
                                    vm.share(card)
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    // Hook to an edit flow if needed
                                    vm.preview(card)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.showDeleteConfirm = card
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Map Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear { vm.reload() }
            .confirmationDialog("Delete this map?",
                                isPresented: Binding(get: { vm.showDeleteConfirm != nil },
                                                     set: { if !$0 { vm.showDeleteConfirm = nil } }),
                                titleVisibility: .visible) {
                if let card = vm.showDeleteConfirm {
                    Button("Delete", role: .destructive) { vm.delete(card) }
                }
                Button("Cancel", role: .cancel) { vm.showDeleteConfirm = nil }
            }
            // Share sheet
            .sheet(isPresented: Binding(get: { vm.shareItem != nil }, set: { if !$0 { vm.shareItem = nil } })) {
                if let url = vm.shareItem {
                    ShareSheet(items: [url])
                }
            }
            // Image preview sheet
            .sheet(item: $vm.previewing) { card in
                MapPreviewSheet(card: card)
            }
        }
    }
}

// MARK: - Helpers

private struct MapPreviewSheet: View {
    let card: MapEditorViewModel.MapCard
    var body: some View {
        NavigationStack {
            Group {
                if let url = card.pngURL, let img = UIImage(contentsOfFile: url.path) {
                    ScrollView([.vertical, .horizontal]) {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding()
                    }
                } else {
                    ContentUnavailableView("No preview available", systemImage: "photo.on.rectangle", description: Text("This map has no PNG snapshot."))
                }
            }
            .navigationTitle(card.title.isEmpty ? "Map" : card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { UIApplication.shared.firstKeyWindow?.rootViewController?.dismiss(animated: true) }
                }
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? { connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow } }
}
