import CoreAudio
import Foundation
import ServiceManagement

/// Central state: watches CoreAudio and keeps the default devices on the highest-priority
/// connected device for each direction.
@MainActor
final class RouteController: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var currentOutput: AudioDevice?
    @Published private(set) var currentInput: AudioDevice?
    @Published private(set) var lastAction: String?
    @Published var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            PreferencesStore.save(prefs)
            scheduleEnforce()
        }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var listenerTokens: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var pendingEnforce: DispatchWorkItem?

    init() {
        prefs = PreferencesStore.load()
        refresh()
        listenerTokens = AudioSystem.addListeners { [weak self] in
            // Listener is delivered on the main queue.
            MainActor.assumeIsolated {
                self?.refresh()
                self?.scheduleEnforce()
            }
        }
        enforce()
    }

    deinit {
        let tokens = listenerTokens
        AudioSystem.removeListeners(tokens)
    }

    // MARK: Queries

    func current(_ d: Direction) -> AudioDevice? { d == .output ? currentOutput : currentInput }

    func connectedDevice(uid: String) -> AudioDevice? { devices.first { $0.uid == uid } }

    /// Connected devices for a direction, sorted by the user's priority order.
    func connectedByPriority(_ d: Direction) -> [AudioDevice] {
        prefs.list(d).compactMap { entry in
            connectedDevice(uid: entry.uid).flatMap { $0.supports(d) ? $0 : nil }
        }
    }

    // MARK: Actions

    /// User picked a device from the menu: make it #1 in the list and switch to it.
    func promoteAndSelect(_ device: AudioDevice, for d: Direction) {
        var list = prefs.list(d)
        if let idx = list.firstIndex(where: { $0.uid == device.uid }) {
            var entry = list.remove(at: idx)
            entry.enabled = true
            list.insert(entry, at: 0)
        }
        prefs.setList(d, list)
        switchTo(device, for: d)
    }

    func move(_ d: Direction, from: IndexSet, to: Int) {
        var list = prefs.list(d)
        list.move(fromOffsets: from, toOffset: to)
        prefs.setList(d, list)
    }

    func remove(_ d: Direction, uid: String) {
        prefs.setList(d, prefs.list(d).filter { $0.uid != uid })
    }

    func setEnabled(_ d: Direction, uid: String, _ enabled: Bool) {
        var list = prefs.list(d)
        guard let idx = list.firstIndex(where: { $0.uid == uid }) else { return }
        list[idx].enabled = enabled
        prefs.setList(d, list)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastAction = "Launch at login failed: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Internals

    private func refresh() {
        devices = AudioSystem.devices()
        let outID = AudioSystem.defaultDevice(.output)
        let inID = AudioSystem.defaultDevice(.input)
        currentOutput = devices.first { $0.id == outID }
        currentInput = devices.first { $0.id == inID }
        learnNewDevices()
    }

    /// Any device we have never seen gets appended to the bottom of its list(s),
    /// and names of known devices are kept fresh.
    private func learnNewDevices() {
        var updated = prefs
        for d in Direction.allCases {
            var list = updated.list(d)
            var candidates = devices.filter { $0.supports(d) }
            // First run: start with whatever is in use now, so we don't switch away from it.
            if list.isEmpty, let cur = current(d) {
                candidates.sort { a, _ in a.uid == cur.uid }
            }
            for device in candidates {
                if let idx = list.firstIndex(where: { $0.uid == device.uid }) {
                    list[idx].name = device.name
                    list[idx].transport = device.transport
                } else {
                    list.append(PriorityEntry(uid: device.uid, name: device.name, transport: device.transport))
                }
            }
            updated.setList(d, list)
        }
        if updated != prefs { prefs = updated }
    }

    /// macOS often changes defaults in several quick steps (e.g. Bluetooth profile switching),
    /// so wait a moment for things to settle before correcting.
    private func scheduleEnforce() {
        pendingEnforce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.enforce() }
        }
        pendingEnforce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func enforce() {
        for d in Direction.allCases where prefs.isAuto(d) {
            let preferred = prefs.list(d).lazy
                .filter(\.enabled)
                .compactMap { self.connectedDevice(uid: $0.uid) }
                .first { $0.supports(d) }
            guard let target = preferred, current(d)?.uid != target.uid else { continue }
            switchTo(target, for: d)
        }
    }

    private func switchTo(_ device: AudioDevice, for d: Direction) {
        if AudioSystem.setDefault(device.id, for: d, includeSystemSounds: prefs.systemSoundsFollowOutput) {
            let time = Date().formatted(date: .omitted, time: .shortened)
            lastAction = "\(time) — \(d.title) → \(device.name)"
        } else {
            lastAction = "Could not switch \(d.title.lowercased()) to \(device.name)"
        }
        refresh()
    }
}
