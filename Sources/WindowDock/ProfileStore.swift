import DockCore
import Foundation

final class ProfileStore {
    let builtInLayouts = ZoneLayout.builtIns
    private(set) var customLayouts: [ZoneLayout]

    var layouts: [ZoneLayout] {
        builtInLayouts + customLayouts
    }

    private let defaults: UserDefaults
    private let selectionsKey = "profileSelectionsByDisplay"
    private let customLayoutsKey = "customZoneLayouts"
    private var selections: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selections = defaults.dictionary(forKey: selectionsKey)?.compactMapValues { $0 as? String } ?? [:]
        if let data = defaults.data(forKey: customLayoutsKey),
           let layouts = try? JSONDecoder().decode([ZoneLayout].self, from: data) {
            self.customLayouts = layouts
        } else {
            self.customLayouts = []
        }
    }

    func layout(for display: DisplayDescriptor) -> ZoneLayout {
        guard let selectedID = selections[display.id],
              let layout = layouts.first(where: { $0.id == selectedID }) else {
            return .twoColumns
        }
        return layout
    }

    func select(layoutID: String, for display: DisplayDescriptor) {
        guard layouts.contains(where: { $0.id == layoutID }) else { return }
        selections[display.id] = layoutID
        defaults.set(selections, forKey: selectionsKey)
    }

    func saveCustomLayout(_ layout: ZoneLayout) {
        guard layout.id.hasPrefix("custom-"),
              !layout.zones.isEmpty,
              layout.overlappingZoneIDs.isEmpty else {
            return
        }

        if let index = customLayouts.firstIndex(where: { $0.id == layout.id }) {
            customLayouts[index] = layout
        } else {
            customLayouts.append(layout)
        }

        persistCustomLayouts()
    }

    @discardableResult
    func deleteCustomLayout(id layoutID: String) -> Bool {
        guard let index = customLayouts.firstIndex(where: { $0.id == layoutID }) else {
            return false
        }

        customLayouts.remove(at: index)
        selections = selections.filter { $0.value != layoutID }
        persistCustomLayouts()
        defaults.set(selections, forKey: selectionsKey)
        return true
    }

    private func persistCustomLayouts() {
        if let data = try? JSONEncoder().encode(customLayouts) {
            defaults.set(data, forKey: customLayoutsKey)
        }
    }
}
