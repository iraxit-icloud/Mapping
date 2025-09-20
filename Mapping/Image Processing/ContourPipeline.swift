//
//  ContourPipeline.swift
//  Mapping
//
//  Created by Indraneel Rakshit on 9/19/25.
//


import Foundation

/// End-to-end smoother: from Map2D.grid to smooth contours
enum ContourPipeline {
    static func smoothContours(from map: Map2D) -> [[Point]] {
        let w = map.spec.width, h = map.spec.height
        let bin = Morphology.closeGaps(map.grid, w: w, h: h)
        let raw = MarchingSquares.traceContours(bin, w: w, h: h)
        return raw.map { poly in
            let simplified = PolylineOps.rdp(poly, epsilon: 0.8)
            return PolylineOps.chaikin(simplified, iterations: 2)
        }
    }
}
