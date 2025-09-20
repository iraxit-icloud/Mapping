import Foundation
import SwiftUI

@MainActor
final class MapEditorViewModel: ObservableObject {

    struct MapCard: Identifiable, Equatable {
        let id: UUID
        let title: String
        let createdAt: Date
        let jsonURL: URL
        let pngURL: URL?
        let svgURL: URL?
    }

    @Published var maps: [MapCard] = []
    @Published var previewing: MapCard?
    @Published var shareItem: URL?
    @Published var showDeleteConfirm: MapCard?

    func reload() {
        do {
            maps = try listMaps()
        } catch {
            maps = []
        }
    }

    func delete(_ card: MapCard) {
        let fm = FileManager.default
        if fm.fileExists(atPath: card.jsonURL.path) { try? fm.removeItem(at: card.jsonURL) }
        if let p = card.pngURL, fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        if let s = card.svgURL, fm.fileExists(atPath: s.path) { try? fm.removeItem(at: s) }
        reload()
    }

    func preview(_ card: MapCard) { previewing = card }

    func share(_ card: MapCard) {
        if let png = card.pngURL { shareItem = png } else { shareItem = card.jsonURL }
    }

    func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    // MARK: - Private

    private func listMaps() throws -> [MapCard] {
        let fm = FileManager.default
        let dir = try documentsDirectory()
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        let jsons = files.filter { $0.pathExtension.lowercased() == "json" }

        var out: [MapCard] = []
        for json in jsons {
            guard let (id, title) = parseMapJSONHeader(json) else { continue }
            let rvs = try? json.resourceValues(forKeys: [.creationDateKey])
            let created = rvs?.creationDate ?? Date()
            let png = guessPNG(for: id, near: json)
            let svg = guessSVG(for: id, near: json)
            out.append(.init(id: id, title: title.isEmpty ? "Untitled" : title, createdAt: created, jsonURL: json, pngURL: png, svgURL: svg))
        }
        out.sort { $0.createdAt > $1.createdAt }
        return out
    }

    private func documentsDirectory() throws -> URL {
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first { return url }
        throw NSError(domain: "MapEditorViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Documents directory not found"])
    }

    private func parseMapJSONHeader(_ url: URL) -> (UUID, String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let idString = (obj["id"] as? String) ?? (obj["mapId"] as? String)
        guard let idString, let id = UUID(uuidString: idString) else { return nil }
        let title = (obj["title"] as? String) ?? "Map"
        return (id, title)
    }

    private func guessPNG(for id: UUID, near json: URL) -> URL? {
        let fm = FileManager.default
        let candidate1 = json.deletingLastPathComponent().appendingPathComponent("\(id.uuidString).png")
        if fm.fileExists(atPath: candidate1.path) { return candidate1 }
        if let url = try? MapStorage.pngURL(for: id), fm.fileExists(atPath: url.path) { return url }
        return nil
    }

    private func guessSVG(for id: UUID, near json: URL) -> URL? {
        let fm = FileManager.default
        let candidate1 = json.deletingLastPathComponent().appendingPathComponent("\(id.uuidString).svg")
        if fm.fileExists(atPath: candidate1.path) { return candidate1 }
        if let url = try? MapStorage.svgURL(for: id), fm.fileExists(atPath: url.path) { return url }
        return nil
    }
}
