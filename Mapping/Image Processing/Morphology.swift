//
//  Morphology.swift
//  Mapping
//
//  Created by Indraneel Rakshit on 9/19/25.
//


import Foundation

/// Simple binary morphology (dilate/erode) to close gaps in occupancy grids
enum Morphology {
    static func dilate(_ src: [UInt8], w: Int, h: Int) -> [UInt8] {
        var out = src
        let nbr = [(-1,-1),(0,-1),(1,-1),
                   (-1, 0),(0, 0),(1, 0),
                   (-1, 1),(0, 1),(1, 1)]
        for y in 1..<h-1 {
            for x in 1..<w-1 {
                var v: UInt8 = 0
                for (dx,dy) in nbr {
                    let i = (y+dy)*w + (x+dx)
                    v = max(v, src[i])
                }
                out[y*w+x] = v
            }
        }
        return out
    }

    static func erode(_ src: [UInt8], w: Int, h: Int) -> [UInt8] {
        var out = src
        let nbr = [(-1,-1),(0,-1),(1,-1),
                   (-1, 0),(0, 0),(1, 0),
                   (-1, 1),(0, 1),(1, 1)]
        for y in 1..<h-1 {
            for x in 1..<w-1 {
                var v: UInt8 = 1
                for (dx,dy) in nbr {
                    let i = (y+dy)*w + (x+dx)
                    v = min(v, src[i])
                }
                out[y*w+x] = v
            }
        }
        return out
    }

    static func closeGaps(_ grid: [Cell], w: Int, h: Int) -> [UInt8] {
        var bin = grid.map { $0 == .wall ? UInt8(1) : UInt8(0) }
        bin = dilate(bin, w: w, h: h)
        bin = erode(bin,  w: w, h: h)
        return bin
    }
}
