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

        // A plain List (not a grouped Form) is required for drag-to-reorder on macOS.
        VStack(alignment: .leading, spacing: 8) {
            Text("\(direction.title) Priority")
                .font(.headline)

            List {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    PriorityRow(direction: direction, rank: index + 1, entry: entry)
                }
                .onMove { router.move(direction, from: $0, to: $1) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()

            Text("Drag to reorder. The highest enabled device that is connected is used. Turn a device off to never select it automatically. Right-click for more options.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}

private struct PriorityRow: View {
    @EnvironmentObject private var router: RouteController
    let direction: Direction
    let rank: Int
    let entry: PriorityEntry
    private var count: Int { router.prefs.list(direction).count }

    var body: some View {
        let connected = router.connectedDevice(uid: entry.uid) != nil
        let inUse = router.current(direction)?.uid == entry.uid

        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text("\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Image(systemName: AudioSystem.symbol(forTransport: entry.transport))
                .foregroundStyle(connected ? Color.accentColor : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                Text(inUse ? "In Use" : connected ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Use automatically", isOn: Binding(
                get: { entry.enabled },
                set: { router.setEnabled(direction, uid: entry.uid, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .opacity(entry.enabled ? 1 : 0.55)
        .contextMenu {
            Button("Move to Top") {
                if let i = router.prefs.list(direction).firstIndex(of: entry) {
                    router.move(direction, from: [i], to: 0)
                }
            }
            .disabled(rank == 1)
            Button("Move Up") { router.move(direction, from: [rank - 1], to: rank - 2) }
                .disabled(rank == 1)
            Button("Move Down") { router.move(direction, from: [rank - 1], to: rank + 1) }
                .disabled(rank == count)
            Divider()
            Button("Forget Device", role: .destructive) {
                router.remove(direction, uid: entry.uid)
            }
            .disabled(connected)
        }
    }
}
