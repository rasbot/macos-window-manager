import CoreGraphics
import Testing
@testable import DockCore

@Test func twoColumnFramesRespectBoundsAndGap() {
    let bounds = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let frames = ZoneLayout.twoColumns.frames(in: bounds)

    #expect(frames.count == 2)
    #expect(frames[0] == CGRect(x: 104, y: 54, width: 592, height: 792))
    #expect(frames[1] == CGRect(x: 704, y: 54, width: 592, height: 792))
}

@Test func coordinateConversionUsesPrimaryScreenTop() {
    let converter = ScreenCoordinateConverter(primaryScreenTop: 1080)

    #expect(
        converter.appKitPoint(fromQuartz: CGPoint(x: 20, y: 100))
            == CGPoint(x: 20, y: 980)
    )
    #expect(
        converter.accessibilityRect(fromAppKit: CGRect(x: 50, y: 80, width: 400, height: 300))
            == CGRect(x: 50, y: 700, width: 400, height: 300)
    )
}

@Test func builtInLayoutsHaveUniqueIDsAndValidZones() {
    #expect(ZoneLayout.builtIns.count == 5)
    #expect(Set(ZoneLayout.builtIns.map(\.id)).count == ZoneLayout.builtIns.count)

    for layout in ZoneLayout.builtIns {
        #expect(!layout.zones.isEmpty)
        #expect(layout.overlappingZoneIDs.isEmpty)
        for zone in layout.zones {
            #expect(zone.x >= 0)
            #expect(zone.y >= 0)
            #expect(zone.width > 0)
            #expect(zone.height > 0)
            #expect(zone.x + zone.width <= 1.000_001)
            #expect(zone.y + zone.height <= 1.000_001)
        }
    }
}

@Test func overlapDetectionIgnoresSharedEdgesButFindsIntersection() {
    let touching = ZoneLayout(
        id: "touching",
        name: "Touching",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 0.5, height: 1),
            NormalizedZone(id: 2, x: 0.5, y: 0, width: 0.5, height: 1)
        ]
    )
    #expect(touching.overlappingZoneIDs.isEmpty)

    let overlapping = ZoneLayout(
        id: "overlapping",
        name: "Overlapping",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 0.6, height: 1),
            NormalizedZone(id: 2, x: 0.5, y: 0, width: 0.5, height: 1)
        ]
    )
    #expect(overlapping.overlappingZoneIDs == Set([1, 2]))
}
