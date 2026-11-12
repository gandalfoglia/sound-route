import AppKit
import SwiftUI

/// Contents of the menu bar menu. Rendered by the system as a regular NSMenu.
struct MenuContent: View {
    @EnvironmentObject private var router: RouteController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(Direction.allCases) { direction in
            Section(direction.title) {
                Picker(direction.title, selection: selection(for: direction)) {
                    ForEach(router.connectedByPriority(direction)) { device in
                        Label(device.name, systemImage: device.symbol).tag(device.uid)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Toggle("Auto-Switch \(direction.title)", isOn: Binding(
                    get: { router.prefs.isAuto(direction) },
                    set: { router.prefs.setAuto(direction, $0) }
                ))
            }
        }

        if let last = router.lastAction {
            Divider()
            Text(last)
        }

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit SoundRoute") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Choosing a device in the menu uses it now and makes it the top priority.
    private func selection(for direction: Direction) -> Binding<String> {
        Binding(
            get: { router.current(direction)?.uid ?? "" },
            set: { uid in
                if let device = router.connectedDevice(uid: uid) {
                    router.promoteAndSelect(device, for: direction)
                }
            }
        )
    }
}
