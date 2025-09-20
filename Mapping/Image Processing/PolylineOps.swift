//
//  PolylineOps.swift
//  Mapping
//
//  Created by Indraneel Rakshit on 9/19/25.
//


import Foundation

/// Polyline simplification and smoothing
enum PolylineOps {
    static func rdp(_ pts: [Point], epsilon: Float) -> [Point] {
        guard pts.count > 2 else { return pts }
        var dmax: Float = 0
        var idx = 0
        let a = pts.first!, b = pts.last!
        func perp(_ p: Point, _ a: Point, _ b: Point) -> Float {
            let num = abs((b.y - a.y)*p.x - (b.x - a.x)*p.y + b.x*a.y - b.y*a.x)
            let den = hypotf(b.x - a.x, b.y - a.y)
            return den == 0 ? 0 : num / den
        }
        for i in 1..<pts.count-1 {
            let d = perp(pts[i], a, b)
            if d > dmax { dmax = d; idx = i }
        }
        if dmax > epsilon {
            let rec1 = rdp(Array(pts[0...idx]), epsilon: epsilon)
            let rec2 = rdp(Array(pts[idx...]), epsilon: epsilon)
            return Array(rec1.dropLast()) + rec2
        } else {
            return [a, b]
        }
    }

    static func chaikin(_ poly: [Point], iterations: Int = 2) -> [Point] {
        guard poly.count >= 3 else { return poly }
        var out = poly
        for _ in 0..<iterations {
            var next: [Point] = []
            for i in 0..<out.count-1 {
                let p = out[i], q = out[i+1]
                let P = Point(x: 0.75*p.x + 0.25*q.x, y: 0.75*p.y + 0.25*q.y)
                let Q = Point(x: 0.25*p.x + 0.75*q.x, y: 0.25*p.y + 0.75*q.y)
                next.append(P); next.append(Q)
            }
            out = next
        }
        return out
    }
}
