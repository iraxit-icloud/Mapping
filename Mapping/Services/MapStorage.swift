import Foundation
import UIKit

enum MapStorage {
    // MARK: - Directory Helpers

    private static func mapsDirectoryURL() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("Maps", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - File URLs

    static func jsonURL(for id: UUID) throws -> URL {
        try mapsDirectoryURL().appendingPathComponent("\(id).json")
    }

    static func pngURL(for id: UUID) throws -> URL {
        try mapsDirectoryURL().appendingPathComponent("\(id).png")
    }

    static func svgURL(for id: UUID) throws -> URL {
        try mapsDirectoryURL().appendingPathComponent("\(id).svg")
    }

    // MARK: - Save / Load

    static func save(_ map: Map2D) throws {
        let url = try jsonURL(for: map.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(map).write(to: url, options: .atomic)
    }

    static func load(id: UUID) throws -> Map2D {
        let url = try jsonURL(for: id)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Map2D.self, from: data)
    }

    // MARK: - Listing

    static func listSavedMaps() throws -> [UUID] {
        let dir = try mapsDirectoryURL()
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    static func creationDate(for id: UUID) -> Date? {
        guard let url = try? jsonURL(for: id) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.creationDate] as? Date
    }

    // MARK: - Delete

    static func delete(id: UUID) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: try jsonURL(for: id))
        try? fm.removeItem(at: try pngURL(for: id))
        try? fm.removeItem(at: try svgURL(for: id))
    }
}
