import Foundation

/// One device in a priority list. Remembered by UID even while unplugged.
struct PriorityEntry: Codable, Identifiable, Hashable {
    var uid: String
    var name: String
    /// When false the device is skipped by auto-switching (but kept in the list).
    var enabled: Bool = true
    var transport: UInt32 = 0

    var id: String { uid }
}

struct Preferences: Codable, Equatable {
    var outputPriority: [PriorityEntry] = []
    var inputPriority: [PriorityEntry] = []
    var autoOutput = true
    var autoInput = true
    /// Also move alert / system sounds to the chosen output.
    var systemSoundsFollowOutput = true

    func list(_ d: Direction) -> [PriorityEntry] {
        d == .output ? outputPriority : inputPriority
    }

    mutating func setList(_ d: Direction, _ list: [PriorityEntry]) {
        if d == .output { outputPriority = list } else { inputPriority = list }
    }

    func isAuto(_ d: Direction) -> Bool { d == .output ? autoOutput : autoInput }

    mutating func setAuto(_ d: Direction, _ on: Bool) {
        if d == .output { autoOutput = on } else { autoInput = on }
    }
}

/// Stores preferences as JSON in the app's own UserDefaults domain. Nothing leaves the machine.
enum PreferencesStore {
    private static let key = "preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return prefs
    }

    static func save(_ prefs: Preferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
