import CidreBridge
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
    /// La langue de l'interface : "" (celle de macOS), "fr" ou "en".
    @AppStorage("langue") private var language = ""

    init() {
        L10n.language = UserDefaults.standard.string(forKey: "langue").flatMap { $0.isEmpty ? nil : $0 }
        // Lance hors d'un bundle (`swift run`), le processus n'a ni Dock ni
        // fenetre au premier plan : on le declare application a part entiere.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("Verger", id: "bibliotheque") {
            localized(LibraryView())
        }
        .defaultSize(width: 1000, height: 680)

        Settings {
            localized(SettingsView())
        }
    }

    /// Met une fenetre dans la langue choisie. Les textes SwiftUI suivent
    /// `\.locale` ; ceux fabriques a la main suivent `L10n`. Changer de langue
    /// reconstruit la fenetre (`id`) pour que tout se redise dans la nouvelle.
    private func localized(_ content: some View) -> some View {
        content
            .environment(library)
            .environment(updater)
            .environment(\.locale, L10n.locale)
            .id(language)
            .onChange(of: language, initial: true) { _, chosen in
                L10n.language = chosen.isEmpty ? nil : chosen
                // Les menus de macOS (Verger, Fenetre...) ne changent qu'a la relance.
                if chosen.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([chosen], forKey: "AppleLanguages")
                }
            }
    }
}
