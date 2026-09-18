import CoreGraphics
import Foundation

public struct NormalizedZone: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(id: Int, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ZoneLayout: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let zones: [NormalizedZone]
    public let gap: Double

    public init(id: String, name: String, zones: [NormalizedZone], gap: Double = 8) {
        self.id = id
        self.name = name
        self.zones = zones
        self.gap = gap
    }

    public static let twoColumns = ZoneLayout(
        id: "two-columns",
        name: "Two Columns",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 0.5, height: 1),
            NormalizedZone(id: 2, x: 0.5, y: 0, width: 0.5, height: 1)
        ]
    )

    public static let threeColumns = ZoneLayout(
        id: "three-columns",
        name: "Three Columns",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 1.0 / 3.0, height: 1),
            NormalizedZone(id: 2, x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1),
            NormalizedZone(id: 3, x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        ]
    )

    public static let mainAndStack = ZoneLayout(
        id: "main-and-stack",
        name: "Main + Stack",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 2.0 / 3.0, height: 1),
            NormalizedZone(id: 2, x: 2.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5),
            NormalizedZone(id: 3, x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.5)
        ]
    )

    public static let fourQuadrants = ZoneLayout(
        id: "four-quadrants",
        name: "Four Quadrants",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0.5, width: 0.5, height: 0.5),
            NormalizedZone(id: 2, x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            NormalizedZone(id: 3, x: 0, y: 0, width: 0.5, height: 0.5),
            NormalizedZone(id: 4, x: 0.5, y: 0, width: 0.5, height: 0.5)
        ]
    )

    public static let twoThirdsOneThird = ZoneLayout(
        id: "two-thirds-one-third",
        name: "Two Thirds + One Third",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 2.0 / 3.0, height: 1),
            NormalizedZone(id: 2, x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        ]
    )

    public static let builtIns: [ZoneLayout] = [
        .twoColumns,
        .threeColumns,
        .mainAndStack,
        .fourQuadrants,
        .twoThirdsOneThird
    ]

    public var overlappingZoneIDs: Set<Int> {
        var overlappingIDs: Set<Int> = []

        for firstIndex in zones.indices {
            for secondIndex in zones.indices where secondIndex > firstIndex {
                let intersection = normalizedFrame(for: zones[firstIndex])
                    .intersection(normalizedFrame(for: zones[secondIndex]))
                if !intersection.isNull && intersection.width > 0.000_001 && intersection.height > 0.000_001 {
                    overlappingIDs.insert(zones[firstIndex].id)
                    overlappingIDs.insert(zones[secondIndex].id)
                }
            }
        }

        return overlappingIDs
    }

    public func frames(in bounds: CGRect) -> [CGRect] {
        zones.map { zone in
            let x = bounds.origin.x + (bounds.size.width * CGFloat(zone.x))
            let y = bounds.origin.y + (bounds.size.height * CGFloat(zone.y))
            let width = bounds.size.width * CGFloat(zone.width)
            let height = bounds.size.height * CGFloat(zone.height)
            let rawFrame = CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )

            let inset = max(0, gap / 2)
            return rawFrame.insetBy(dx: inset, dy: inset).integral
        }
    }

    private func normalizedFrame(for zone: NormalizedZone) -> CGRect {
        CGRect(x: zone.x, y: zone.y, width: zone.width, height: zone.height)
    }
}
