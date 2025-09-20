import Foundation

enum MapStorage {
    static func baseFolder() throws -> URL {
        let fm = FileManager.default
        let app = try fm.url(for: .applicationSupportDirectory,
                             in: .userDomainMask,
                             appropriateFor: nil,
                             create: true)
        let dir = app.appendingPathComponent("IndoorMaps", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func jsonURL(for id: UUID) throws -> URL { try baseFolder().appendingPathComponent("\(id.uuidString).json") }
    static func pngURL(for id: UUID) throws -> URL  { try baseFolder().appendingPathComponent("\(id.uuidString).png")  }
    static func svgURL(for id: UUID) throws -> URL  { try baseFolder().appendingPathComponent("\(id.uuidString).svg")  }

    // ✅ Pretty-print + safe non-finite floats (handles NaN in DistanceField)
    static func save(_ map: Map2D) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity",
                                                                  negativeInfinity: "-Infinity",
                                                                  nan: "NaN")
        let data = try enc.encode(map)
        try data.write(to: try jsonURL(for: map.id), options: .atomic)
    }

    static func load(id: UUID) throws -> Map2D {
        let data = try Data(contentsOf: try jsonURL(for: id))
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity",
                                                                    negativeInfinity: "-Infinity",
                                                                    nan: "NaN")
        return try dec.decode(Map2D.self, from: data)
    }

    static func list() throws -> [UUID] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: try baseFolder(), includingPropertiesForKeys: nil)
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            return id
        }
    }
}
