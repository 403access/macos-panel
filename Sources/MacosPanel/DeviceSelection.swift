import Foundation

/// Device IDs whose charge is shown in the menu bar. Stored as a JSON array so the
/// selection survives app launches and disconnects.
struct DeviceSelection: RawRepresentable, Equatable {
    private(set) var ids: Set<String>

    init() {
        ids = []
    }

    init(ids: Set<String>) {
        self.ids = ids
    }

    init(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            ids = []
            return
        }
        ids = Set(values)
    }

    var rawValue: String {
        let values = ids.sorted()
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    mutating func set(_ id: String, enabled: Bool) {
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
    }
}