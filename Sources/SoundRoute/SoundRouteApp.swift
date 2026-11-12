import SwiftUI

@main
struct SoundRouteApp: App {
    @StateObject private var router = RouteController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(router)
        } label: {
            let auto = router.prefs.autoOutput || router.prefs.autoInput
            Image(systemName: auto ? "speaker.wave.2.fill" : "speaker.wave.2")
                .accessibilityLabel("SoundRoute")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView().environmentObject(router)
        }
    }
}
