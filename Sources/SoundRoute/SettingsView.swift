import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralPane()
            }
            Tab("Output", systemImage: Direction.output.symbol) {
                PriorityPane(direction: .output)
            }
            Tab("Input", systemImage: Direction.input.symbol) {
                PriorityPane(direction: .input)
            }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var router: RouteController

    var body: some View {
        Form {
            Section {
                Toggle("Automatically switch output", isOn: $router.prefs.autoOutput)
                Toggle("Automatically switch input", isOn: $router.prefs.autoInput)
            } header: {
                Text("Automatic Switching")
            } footer: {
                Text("When devices connect or disconnect, or macOS changes the default device, SoundRoute switches back to your highest-priority available device.")
            }

            Section {
                Toggle("Play alerts and sound effects through the output device", isOn: $router.prefs.systemSoundsFollowOutput)
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { router.launchAtLogin },
                    set: { router.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Priority lists

private struct PriorityPane: View {
    @EnvironmentObject private var router: RouteController
    let direction: Direction

    var body: some View {
        let entries = router.prefs.list(direction)

        Form {
            Section {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    PriorityRow(direction: direction, rank: index + 1, entry: entry)
                }
                .onMove { router.move(direction, from: $0, to: $1) }
            } header: {
                Text("\(direction.title) Priority")
            } footer: {
                Text("Drag to reorder. The highest enabled device that is connected is used. Turn a device off to never select it automatically.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PriorityRow: View {
    @EnvironmentObject private var router: RouteController
    let direction: Direction
    let rank: Int
    let entry: PriorityEntry

    var body: some View {
        let connected = router.connectedDevice(uid: entry.uid) != nil
        let inUse = router.current(direction)?.uid == entry.uid

        Toggle(isOn: Binding(
            get: { entry.enabled },
            set: { router.setEnabled(direction, uid: entry.uid, $0) }
        )) {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
                Image(systemName: AudioSystem.symbol(forTransport: entry.transport))
                    .foregroundStyle(connected ? Color.accentColor : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    Text(inUse ? "In Use" : connected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .contextMenu {
            Button("Move to Top") {
                if let i = router.prefs.list(direction).firstIndex(of: entry) {
                    router.move(direction, from: [i], to: 0)
                }
            }
            .disabled(rank == 1)
            Button("Forget Device", role: .destructive) {
                router.remove(direction, uid: entry.uid)
            }
            .disabled(connected)
        }
    }
}
