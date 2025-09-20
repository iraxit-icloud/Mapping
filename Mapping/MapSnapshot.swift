import UIKit

enum MapSnapshot {
    /// Render occupancy (raster), doorways (blue), beacons (green),
    /// and a smooth outline (teal) vectorized from the grid.
    static func png(from map: Map2D, target: CGFloat = 1024, scale: CGFloat = 2) -> Data? {
        let w = CGFloat(map.spec.width), h = CGFloat(map.spec.height)
        let s = min(target / w, target / h)
        let size = CGSize(width: w * s, height: h * s)

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: Int(size.width * scale),
                                  height: Int(size.height * scale),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        // Background
        ctx.setFillColor(UIColor.systemBackground.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // --- Raster walls (from grid) ---
        ctx.setFillColor(UIColor.label.withAlphaComponent(0.8).cgColor)
        for y in 0..<map.spec.height {
            for x in 0..<map.spec.width {
                if map.grid[map.idx(x, y)] == .wall {
                    let r = CGRect(x: CGFloat(x)*s, y: CGFloat(y)*s, width: s, height: s)
                    ctx.fill(r)
                }
            }
        }

        // --- Smooth outline (vector) — minimal integration ---
        // Requires ContourPipeline.swift + its helpers dropped into the project.
        let contours = ContourPipeline.smoothContours(from: map)
        if !contours.isEmpty {
            ctx.setStrokeColor(UIColor.systemTeal.cgColor)
            ctx.setLineWidth(max(1, s * 0.6))      // thin but visible at any scale
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)

            for c in contours {
                guard let first = c.first else { continue }
                ctx.beginPath()
                ctx.move(to: CGPoint(x: CGFloat(first.x) * s, y: CGFloat(first.y) * s))
                for p in c.dropFirst() {
                    ctx.addLine(to: CGPoint(x: CGFloat(p.x) * s, y: CGFloat(p.y) * s))
                }
                ctx.strokePath()
            }
        }

        // --- Doorways ---
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(max(1, s))
        for d in map.doorways {
            let a = toPixel(d.a, map, s)
            let b = toPixel(d.b, map, s)
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        }

        // --- Beacons ---
        ctx.setFillColor(UIColor.systemGreen.cgColor)
        for b in map.beacons {
            let p = toPixel(b.position, map, s)
            let r = max(3, s * 0.45)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2))
        }

        guard let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    /// Simple, sharable SVG (unchanged): raster-style cells + vectors for doors/beacons.
    /// (If you want the smooth outline in SVG too, say the word and I’ll add it.)
    static func svg(from map: Map2D) -> Data? {
        let w = map.spec.width, h = map.spec.height
        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <rect width="100%" height="100%" fill="white"/>
          <g fill="black" fill-opacity="0.8">
        """
        for y in 0..<h {
            for x in 0..<w {
                if map.grid[map.idx(x, y)] == .wall {
                    out += "<rect x='\(x)' y='\(y)' width='1' height='1'/>"
                }
            }
        }
        out += "</g><g stroke='blue' stroke-width='1'>"
        for d in map.doorways {
            let ax = (d.a.x - map.spec.originWorldXZ.x)/map.spec.resolution + 0.5
            let ay = (d.a.y - map.spec.originWorldXZ.y)/map.spec.resolution + 0.5
            let bx = (d.b.x - map.spec.originWorldXZ.x)/map.spec.resolution + 0.5
            let by = (d.b.y - map.spec.originWorldXZ.y)/map.spec.resolution + 0.5
            out += "<line x1='\(ax)' y1='\(ay)' x2='\(bx)' y2='\(by)'/>"
        }
        out += "</g><g fill='green'>"
        for b in map.beacons {
            let cx = (b.position.x - map.spec.originWorldXZ.x)/map.spec.resolution + 0.5
            let cy = (b.position.y - map.spec.originWorldXZ.y)/map.spec.resolution + 0.5
            out += "<circle cx='\(cx)' cy='\(cy)' r='0.5'/>"
        }
        out += "</g></svg>"
        return out.data(using: .utf8)
    }

    @inline(__always)
    private static func toPixel(_ worldXZ: SIMD2<Float>, _ map: Map2D, _ s: CGFloat) -> CGPoint {
        let gx = (CGFloat((worldXZ.x - map.spec.originWorldXZ.x) / map.spec.resolution) + 0.5) * s
        let gy = (CGFloat((worldXZ.y - map.spec.originWorldXZ.y) / map.spec.resolution) + 0.5) * s
        return CGPoint(x: gx, y: gy)
    }
}
