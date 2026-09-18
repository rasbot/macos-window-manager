import Foundation
import Testing
@testable import DockCore

private func customLayout(name: String, gap: Double = 8) -> ZoneLayout {
    ZoneLayout(
        id: ZoneLayout.newCustomID(),
        name: name,
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 0.5, height: 1),
            NormalizedZone(id: 2, x: 0.5, y: 0, width: 0.5, height: 1)
        ],
        gap: gap
    )
}

@Test func archiveRoundTripsThroughJSON() throws {
    let archive = LayoutArchive(layouts: [customLayout(name: "Editing"), customLayout(name: "Review")])
    let decoded = try LayoutArchive.decoded(from: archive.encoded())

    #expect(decoded.version == LayoutArchive.currentVersion)
    #expect(decoded.layouts.map(\.name) == ["Editing", "Review"])
    #expect(decoded.layouts == archive.layouts)
}

@Test func archiveRejectsUnrelatedData() {
    #expect(throws: LayoutArchive.ArchiveError.unreadable) {
        try LayoutArchive.decoded(from: Data("not a profile export".utf8))
    }
}

@Test func archiveRejectsNewerFormats() throws {
    let future = LayoutArchive(layouts: [customLayout(name: "Future")], version: LayoutArchive.currentVersion + 1)
    #expect(throws: LayoutArchive.ArchiveError.unsupportedVersion(LayoutArchive.currentVersion + 1)) {
        try LayoutArchive.decoded(from: future.encoded())
    }
}

@Test func importGivesFreshIdentifiersSoNothingIsOverwritten() throws {
    let existing = customLayout(name: "Editing")
    let archive = LayoutArchive(layouts: [existing])

    let imported = try archive.importableLayouts(alongside: [existing])

    #expect(imported.count == 1)
    #expect(imported[0].id != existing.id)
    #expect(imported[0].isCustom)
    #expect(imported[0].zones == existing.zones)
}

@Test func importNumbersCollidingNames() throws {
    let existing = customLayout(name: "Editing")
    let archive = LayoutArchive(layouts: [customLayout(name: "Editing"), customLayout(name: "Editing")])

    let imported = try archive.importableLayouts(alongside: [existing])

    #expect(imported.map(\.name) == ["Editing 2", "Editing 3"])
}

@Test func importDropsUnusableLayouts() throws {
    let overlapping = ZoneLayout(
        id: ZoneLayout.newCustomID(),
        name: "Overlapping",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 0.8, height: 1),
            NormalizedZone(id: 2, x: 0.5, y: 0, width: 0.5, height: 1)
        ]
    )
    let good = customLayout(name: "Good")

    let imported = try LayoutArchive(layouts: [overlapping, good]).importableLayouts(alongside: [])
    #expect(imported.map(\.name) == ["Good"])

    #expect(throws: LayoutArchive.ArchiveError.noUsableLayouts) {
        try LayoutArchive(layouts: [overlapping]).importableLayouts(alongside: [])
    }
}

@Test func layoutUsabilityCatchesBadGeometry() {
    #expect(customLayout(name: "Fine").isUsable)
    for builtIn in ZoneLayout.builtIns {
        #expect(builtIn.isUsable)
    }

    let unnamed = ZoneLayout(id: ZoneLayout.newCustomID(), name: "  ", zones: customLayout(name: "x").zones)
    #expect(!unnamed.isUsable)

    let empty = ZoneLayout(id: ZoneLayout.newCustomID(), name: "Empty", zones: [])
    #expect(!empty.isUsable)

    let outOfBounds = ZoneLayout(
        id: ZoneLayout.newCustomID(),
        name: "Out of bounds",
        zones: [NormalizedZone(id: 1, x: 0.5, y: 0, width: 0.8, height: 1)]
    )
    #expect(!outOfBounds.isUsable)

    let duplicateIDs = ZoneLayout(
        id: ZoneLayout.newCustomID(),
        name: "Duplicate ids",
        zones: [
            NormalizedZone(id: 1, x: 0, y: 0, width: 0.5, height: 1),
            NormalizedZone(id: 1, x: 0.5, y: 0, width: 0.5, height: 1)
        ]
    )
    #expect(!duplicateIDs.isUsable)

    #expect(!customLayout(name: "Huge gap", gap: 500).isUsable)
}

@Test func duplicationProducesAnIndependentCustomProfile() {
    let original = ZoneLayout.fourQuadrants
    let copy = original.duplicated()

    #expect(copy.isCustom)
    #expect(!original.isCustom)
    #expect(original.isBuiltIn)
    #expect(copy.name == "Four Quadrants Copy")
    #expect(copy.zones == original.zones)
    #expect(copy.duplicated().id != copy.id)
    #expect(copy.renamed("Coding").name == "Coding")
    #expect(copy.renamed("Coding").id == copy.id)
}
