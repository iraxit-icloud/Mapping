import Foundation

/// Extract wall contours from binary occupancy grid
enum MarchingSquares {
    struct EdgeKey: Hashable { let x: Int; let y: Int; let e: Int }

    static func traceContours(_ grid: [UInt8], w: Int, h: Int) -> [[Point]] {
        var paths: [[Point]] = []
        var visited = Set<EdgeKey>()

        func val(_ x:Int,_ y:Int)->UInt8 {
            guard x>=0, y>=0, x<w, y<h else { return 0 }
            return grid[y*w+x]
        }

        // Edge offsets
        let dx = [0,1,0,-1], dy = [0,0,1,0]
        let ex = [0.5,1.0,0.5,0.0], ey = [0.0,0.5,1.0,0.5]

        for y in 0..<h-1 {
            for x in 0..<w-1 {
                let c0 = val(x,y), c1 = val(x+1,y)
                let c2 = val(x+1,y+1), c3 = val(x,y+1)
                let code = Int(c0)<<0 | Int(c1)<<1 | Int(c2)<<2 | Int(c3)<<3
                if code == 0 || code == 15 { continue }

                for startEdge in 0..<4 where !visited.contains(EdgeKey(x:x,y:y,e:startEdge)) {
                    var cx = x, cy = y, e = startEdge
                    var poly: [Point] = []
                    var guardCount = 0

                    while guardCount < 10000 {
                        guardCount += 1
                        poly.append(Point(x: Float(cx)+Float(ex[e]),
                                          y: Float(cy)+Float(ey[e])))

                        // move
                        cx += dx[e]; cy += dy[e]
                        // trivial next edge turn
                        e = (e+1) % 4
                        let key = EdgeKey(x: cx,y: cy,e: e)
                        if visited.contains(key) { break }
                        visited.insert(key)
                    }
                    if poly.count > 2 { paths.append(poly) }
                }
            }
        }
        return paths
    }
}
