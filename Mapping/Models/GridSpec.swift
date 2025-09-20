import Foundation
import simd

public struct GridSpec: Codable, Equatable {
    public var resolution: Float
    public var width: Int
    public var height: Int
    public var originWorldXZ: SIMD2<Float>
}

public enum Cell: UInt8, Codable { case free = 0, wall = 1 }

public struct Doorway: Codable, Identifiable, Hashable {
    public let id: UUID
    public var a: SIMD2<Float>
    public var b: SIMD2<Float>
    public var width: Float
    public init(id: UUID = UUID(), a: SIMD2<Float>, b: SIMD2<Float>, width: Float) {
        self.id = id; self.a = a; self.b = b; self.width = width
    }
}

public struct Beacon: Codable, Identifiable, Hashable {
    public let id: UUID
    public var position: SIMD2<Float>
    public var name: String
    public init(id: UUID = UUID(), position: SIMD2<Float>, name: String) {
        self.id = id; self.position = position; self.name = name
    }
}

public struct DistanceField: Codable, Equatable {
    public var width: Int
    public var height: Int
    public var meters: [Float]
}

public struct Map2D: Codable, Identifiable {   // ⬅️ Identifiable added
    public var id: UUID
    public var title: String
    public var spec: GridSpec
    public var grid: [Cell]
    public var doorways: [Doorway]
    public var beacons: [Beacon]
    public var distanceField: DistanceField?

    public init(id: UUID = UUID(), title: String, spec: GridSpec) {
        self.id = id
        self.title = title
        self.spec = spec
        self.grid = .init(repeating: .free, count: spec.width * spec.height)
        self.doorways = []
        self.beacons = []
        self.distanceField = nil
    }

    @inline(__always) public func idx(_ x: Int, _ y: Int) -> Int { y * spec.width + x }
    public mutating func setCell(x: Int, y: Int, to v: Cell) {
        guard x >= 0, y >= 0, x < spec.width, y < spec.height else { return }
        grid[idx(x, y)] = v
    }
    public func cellAt(x: Int, y: Int) -> Cell? {
        guard x >= 0, y >= 0, x < spec.width, y < spec.height else { return nil }
        return grid[idx(x, y)]
    }
}
