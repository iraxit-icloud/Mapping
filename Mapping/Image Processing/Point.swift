//
//  Point.swift
//  Mapping
//
//  Created by Indraneel Rakshit on 9/19/25.
//


import Foundation

/// Lightweight 2D point (float, map grid space)
public struct Point: Hashable, Codable {
    public var x: Float
    public var y: Float
    public init(x: Float, y: Float) { self.x = x; self.y = y }
}
