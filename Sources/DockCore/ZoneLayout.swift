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

public extension ZoneLayout {
    /// Identifier prefix that marks a layout as user-created rather than built in.
    static let customIDPrefix = "custom-"

    static func newCustomID() -> String {
        "\(customIDPrefix)\(UUID().uuidString)"
    }

    var isCustom: Bool {
        id.hasPrefix(Self.customIDPrefix)
    }

    var isBuiltIn: Bool {
        Self.builtIns.contains { $0.id == id }
    }

    /// Whether every zone sits inside the unit square with a positive size.
    var hasZonesWithinBounds: Bool {
        zones.allSatisfy { zone in
            zone.width > 0
                && zone.height > 0
                && zone.x >= -0.000_001
                && zone.y >= -0.000_001
                && zone.x + zone.width <= 1.000_001
                && zone.y + zone.height <= 1.000_001
        }
    }

    var hasUniqueZoneIDs: Bool {
        Set(zones.map(\.id)).count == zones.count
    }

    /// A layout is usable when it has at least one in-bounds, non-overlapping zone
    /// and a sane gap. Checked before persisting and before importing.
    var isUsable: Bool {
        !zones.isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasZonesWithinBounds
            && hasUniqueZoneIDs
            && overlappingZoneIDs.isEmpty
            && gap >= 0
            && gap <= 200
    }

    /// A copy carrying a fresh custom identifier, used by Duplicate and Import.
    func duplicated(named newName: String? = nil) -> ZoneLayout {
        ZoneLayout(
            id: Self.newCustomID(),
            name: newName ?? "\(name) Copy",
            zones: zones,
            gap: gap
        )
    }

    func renamed(_ newName: String) -> ZoneLayout {
        ZoneLayout(id: id, name: newName, zones: zones, gap: gap)
    }
}
