import SwiftUI

/// Fermer la fenetre quitte Verger. Sans cela le processus survivait a sa
/// fenetre, et rouvrir l'application apres une mise a jour remontrait l'ancien
/// programme reste en memoire, pas le nouveau.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct VergerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var library = LibraryModel()
    @State private var updater = AppUpdateModel()

    init() {
        // Lance hors d'un bundle (`swift run`), le processus n'a ni Dock ni
        // fenetre au premier plan : on le declare application a part entiere.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("Verger", id: "bibliotheque") {
            LibraryView()
                .environment(library)
                .environment(updater)
        }
        .defaultSize(width: 1000, height: 680)

        Settings {
            SettingsView()
                .environment(library)
                .environment(updater)
        }
    }
}
