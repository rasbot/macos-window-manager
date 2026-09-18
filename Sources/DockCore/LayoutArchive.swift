import Foundation

/// The on-disk format for exported profiles.
///
/// Versioned so a future format change can be detected rather than silently
/// decoding into the wrong shape.
public struct LayoutArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let fileExtension = "windockprofiles"

    public let version: Int
    public let exportedAt: Date
    public let layouts: [ZoneLayout]

    public init(layouts: [ZoneLayout], exportedAt: Date = Date(), version: Int = LayoutArchive.currentVersion) {
        self.version = version
        self.exportedAt = exportedAt
        self.layouts = layouts
    }

    public enum ArchiveError: Error, Equatable, LocalizedError {
        case unreadable
        case unsupportedVersion(Int)
        case noUsableLayouts

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                "That file is not a WindowDock profile export."
            case .unsupportedVersion(let version):
                "This export was written by a newer version of WindowDock (format \(version))."
            case .noUsableLayouts:
                "That export contains no usable layouts."
            }
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> LayoutArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(LayoutArchive.self, from: data) else {
            throw ArchiveError.unreadable
        }
        guard archive.version <= currentVersion else {
            throw ArchiveError.unsupportedVersion(archive.version)
        }
        return archive
    }

    /// The layouts from this archive that are safe to add alongside `existing`.
    ///
    /// Unusable layouts are dropped, every layout is given a fresh custom
    /// identifier so an import can never overwrite a profile already on this Mac,
    /// and colliding names are numbered so the menu stays unambiguous.
    public func importableLayouts(alongside existing: [ZoneLayout]) throws -> [ZoneLayout] {
        var takenNames = Set(existing.map(\.name))
        var imported: [ZoneLayout] = []

        for layout in layouts where layout.isUsable {
            imported.append(layout.duplicated(named: Self.uniqueName(for: layout.name, taken: &takenNames)))
        }

        guard !imported.isEmpty else { throw ArchiveError.noUsableLayouts }
        return imported
    }

    private static func uniqueName(for name: String, taken: inout Set<String>) -> String {
        guard taken.contains(name) else {
            taken.insert(name)
            return name
        }

        var suffix = 2
        while taken.contains("\(name) \(suffix)") {
            suffix += 1
        }
        let unique = "\(name) \(suffix)"
        taken.insert(unique)
        return unique
    }
}
