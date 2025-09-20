import SwiftUI

// ========= ScanView (with crosshair + HUD) =========

struct ScanView: View {
    @StateObject var vm = ScanViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ARViewContainer(vm: vm)

                // HUD overlay
                ScanHUD(vm: vm, showPlacementButtons: true)

                // Crosshair overlay
                CrosshairView(state: vm.crosshair)
                    .allowsHitTesting(false)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()

            Divider()

            // Placement controls
            HStack {
                Button {
                    vm.beginBeaconPlacement()
                } label: {
                    Label("Place Beacon", systemImage: "mappin.and.ellipse")
                }

                Button {
                    vm.beginDoorwayPlacement()
                } label: {
                    Label("Place Doorway", systemImage: "rectangle.portrait.split.2x1")
                }

                if vm.placementMode != .none {
                    Button(role: .cancel) { vm.cancelPlacement() } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

struct CrosshairView: View {
    let state: ScanViewModel.CrosshairState
    private var color: Color {
        switch state {
        case .none: return .gray.opacity(0.7)
        case .floorHit: return .green
        case .wallHit: return .blue
        }
    }
    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = 24
            let line: CGFloat = 2
            ZStack {
                Rectangle().fill(color).frame(width: line, height: size)
                Rectangle().fill(color).frame(width: size, height: line)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

// ========= Map list + editor launcher =========

struct MapListView: View {
    @State private var maps: [Map2D] = []
    @State private var editing: Bool = false
    private struct JSONPreviewItem: Identifiable { let id = UUID(); let url: URL }
    @State private var jsonPreview: JSONPreviewItem?

    var body: some View {
        List(maps, id: \.id) { m in
            HStack {
                VStack(alignment: .leading) {
                    Text(m.title).font(.headline)
                    Text("Grid \(m.spec.width)x\(m.spec.height) @ \(String(format: "%.0f", 1/m.spec.resolution)) cells/m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let pngURL = try? MapStorage.pngURL(for: m.id) {
                    ShareLink(item: pngURL) { Image(systemName: "photo") }
                        .buttonStyle(.borderless)
                        .help("Share PNG snapshot")
                }

                if let jsonURL = try? MapStorage.jsonURL(for: m.id) {
                    Button {
                        jsonPreview = JSONPreviewItem(url: jsonURL)
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("View JSON")
                }

                Button {
                    editing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
            }
        }
        // Editor sheet — now just shows MapEditorView with no args
        .sheet(isPresented: $editing) {
            MapEditorView()
        }
        // JSON viewer sheet
        .sheet(item: $jsonPreview) { item in
            NavigationStack {
                JSONViewerView(fileURL: item.url)
                    .navigationBarItems(leading: Button("Close") { jsonPreview = nil })
            }
        }
        .onAppear(perform: reload)
        .navigationTitle("My Maps")
        .navigationBarItems(trailing:
            Button(action: { reload() }) {
                Image(systemName: "arrow.clockwise")
            }
        )
    }

    private func reload() {
        let ids = (try? MapStorage.listSavedMaps()) ?? []   // ⚡ make sure MapStorage has this
        maps = ids.compactMap { try? MapStorage.load(id: $0) }
    }
}

// ========= App entry =========

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Scan 2D Map") { ScanView() }
                NavigationLink("Maps & Editor") { MapListView() }
            }
            .navigationTitle("Indoor 2D Maps")
        }
    }
}

// ========= JSON Viewer =========

struct JSONViewerView: View {
    let fileURL: URL
    @State private var text: String = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let err = loadError {
                Text("Failed to load JSON:\n\(err)")
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy JSON")
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            text = String(data: data, encoding: .utf8) ?? "<binary>"
        } catch {
            loadError = error.localizedDescription
        }
    }
}
