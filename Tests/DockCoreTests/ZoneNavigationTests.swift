import CoreGraphics
import Testing
@testable import DockCore

/// A 1200x800 display laid out as Main + Stack:
/// zone 0 fills the left two thirds, zone 1 is the top right, zone 2 the bottom right.
private let mainAndStackFrames = ZoneLayout.mainAndStack.frames(in: CGRect(x: 0, y: 0, width: 1200, height: 800))

@Test func navigatorFindsZoneUnderPoint() {
    #expect(ZoneNavigator.index(containing: CGPoint(x: 100, y: 400), in: mainAndStackFrames) == 0)
    #expect(ZoneNavigator.index(containing: CGPoint(x: 1000, y: 700), in: mainAndStackFrames) == 1)
    #expect(ZoneNavigator.index(containing: CGPoint(x: 1000, y: 100), in: mainAndStackFrames) == 2)
    #expect(ZoneNavigator.index(containing: CGPoint(x: -50, y: 400), in: mainAndStackFrames) == nil)
}

@Test func navigatorMatchesWindowByCenterThenOverlap() {
    // A window sitting squarely in the bottom-right zone.
    #expect(ZoneNavigator.index(matching: CGRect(x: 820, y: 20, width: 360, height: 360), in: mainAndStackFrames) == 2)

    // A window whose center falls in the gap between zones still matches the zone
    // it overlaps most.
    let straddling = CGRect(x: 700, y: 100, width: 220, height: 200)
    #expect(ZoneNavigator.index(matching: straddling, in: mainAndStackFrames) == 2)

    // A window entirely off the layout falls back to the nearest zone center.
    #expect(ZoneNavigator.index(matching: CGRect(x: 3000, y: 700, width: 100, height: 100), in: mainAndStackFrames) == 1)

    #expect(ZoneNavigator.index(matching: .zero, in: []) == nil)
}

@Test func navigatorMovesToAdjacentZone() {
    // Right from the main zone lands in the stack, and left comes back.
    #expect(ZoneNavigator.index(from: 0, direction: .right, in: mainAndStackFrames) == 1)
    #expect(ZoneNavigator.index(from: 1, direction: .left, in: mainAndStackFrames) == 0)
    #expect(ZoneNavigator.index(from: 2, direction: .left, in: mainAndStackFrames) == 0)

    // Vertical movement only applies within the stacked column.
    #expect(ZoneNavigator.index(from: 1, direction: .down, in: mainAndStackFrames) == 2)
    #expect(ZoneNavigator.index(from: 2, direction: .up, in: mainAndStackFrames) == 1)
}

@Test func navigatorStopsAtLayoutEdges() {
    #expect(ZoneNavigator.index(from: 0, direction: .left, in: mainAndStackFrames) == nil)
    #expect(ZoneNavigator.index(from: 0, direction: .up, in: mainAndStackFrames) == nil)
    #expect(ZoneNavigator.index(from: 1, direction: .right, in: mainAndStackFrames) == nil)
    #expect(ZoneNavigator.index(from: 2, direction: .down, in: mainAndStackFrames) == nil)
    #expect(ZoneNavigator.index(from: 7, direction: .left, in: mainAndStackFrames) == nil)
}

@Test func navigatorPrefersTheNearestZoneAlongTheTravelAxis() {
    let columns = ZoneLayout.threeColumns.frames(in: CGRect(x: 0, y: 0, width: 1200, height: 800))

    // Moving right from the first column must stop at the middle column rather
    // than skipping to the far edge.
    #expect(ZoneNavigator.index(from: 0, direction: .right, in: columns) == 1)
    #expect(ZoneNavigator.index(from: 1, direction: .right, in: columns) == 2)
    #expect(ZoneNavigator.index(from: 2, direction: .left, in: columns) == 1)
}
