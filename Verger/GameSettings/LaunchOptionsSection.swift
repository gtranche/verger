import CidreBridge
import SwiftUI

/// Les options de lancement, pour un jeu ou pour tous (reglages generaux) : des
/// interrupteurs qui ecrivent le profils.toml de l'utilisateur (`cidre set`).
///
/// Trois niveaux, du plus faible au plus fort : ce que livre Cidre, le reglage
/// general de l'utilisateur, le reglage force pour un jeu. Une pastille marque
/// ce qui a ete regle a ce niveau-ci ; la fleche a cote y renonce.
struct LaunchOptionsEditor: View {
    enum Scope {
        case game, general
    }

    /// L'identifiant passe a `cidre set` : celui du jeu, ou `CidreCLI.defaultsID`.
    let targetID: String
    let scope: Scope
    let options: LaunchOptions
    let overridden: Set<LaunchOptions.Key>
    /// Applique une commande a Cidre, puis recharge les options affichees.
    let apply: (@escaping @Sendable (CidreCLI) async throws -> Void) -> Void

    var body: some View {
        // L'interrupteur dit ce que le joueur gagne ; Cidre stocke l'inverse
        // (tso = true : ordre memoire strict).
        toggle("Performance CPU", .tso, isOn: !options.tso, stored: { !$0 },
               help: "Relâche l'ordre mémoire émulé : gros gain CPU, mais certains jeux peuvent planter.")
        toggle("Vsync", .vsync, isOn: options.vsync,
               help: "Désactivée : plus de plafond à 40 ou 30 fps, au prix d'un déchirement possible de l'image.")
        if let fullscreen = options.fullscreen {
            toggle("Vrai plein écran", .fullscreen, isOn: fullscreen,
                   help: "Le jeu occupe tout l'écran, encoche comprise, comme un jeu natif.")
        }
        if let gameMode = options.gameMode {
            toggle("Mode Jeu de macOS", .gameMode, isOn: gameMode,
                   help: "Donne la priorité au jeu (processeur, carte graphique, manette) pendant la partie.")
        }
        if let overlay = options.overlay {
            toggle("Overlay Steam", .overlay, isOn: overlay,
                   help: "Maj+Tab en jeu : amis, succès, guides et notifications de Steam. À couper si un jeu s'affiche mal.")
        }
        if let language = options.language {
            Picker(selection: Binding(
                get: { language },
                set: { value in
                    let id = targetID
                    apply { try await $0.setOption(id: id, .language, to: value) }
                }
            )) {
                Text("Automatique").tag("auto")
                ForEach(Self.gameLanguages, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                if language != "auto", !Self.gameLanguages.contains(where: { $0.code == language }) {
                    Text(verbatim: language).tag(language)
                }
            } label: {
                label("Langue du jeu", .language,
                      help: "Automatique : la langue de macOS et de Steam. Certains jeux n'obéissent qu'à leurs propres réglages.")
            }
        }
        toggle("Compteur fps et charge GPU", .hud, isOn: options.hud,
               help: "Affiche les performances à l'écran, pour voir l'effet d'un réglage.")
        toggle("Shaders compilés en fond", .asyncShaders, isOn: options.asyncShaders,
               help: "Supprime les saccades quand le jeu découvre de nouveaux effets.")
        Picker(selection: threads) {
            Text("Automatique").tag(0)
            ForEach([2, 4, 6, 8], id: \.self) { Text("\($0)").tag($0) }
            if ![0, 2, 4, 6, 8].contains(options.compilerThreads) {
                Text("\(options.compilerThreads)").tag(options.compilerThreads)
            }
        } label: {
            label("Fils de compilation", .compilerThreads,
                  help: "Limiter évite qu'un gros chargement n'étouffe le jeu.")
        }
        toggle("Anti-triche permissif", .eacUntrusted, isOn: options.eacUntrusted,
               help: "Lance le jeu en mode « Modded » (-eac-untrusted) : pas de jeu en ligne officiel.")
        toggle("Correctif LuaJIT", .luajit, isOn: options.luajit,
               help: "Requis par certains jeux (Vermintide 2), inutile aux autres.")

        if !overridden.isEmpty {
            Button(scope == .game ? "Ne plus rien forcer pour ce jeu" : "Rétablir les réglages de Cidre") {
                let id = targetID
                apply { try await $0.resetOptions(id: id) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Les langues proposees pour un jeu, nommees dans leur propre langue.
    private static let gameLanguages: [(code: String, name: String)] = [
        ("fr", "Français"), ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("it", "Italiano"),
        ("pt", "Português"), ("ru", "Русский"), ("pl", "Polski"), ("ja", "日本語"), ("ko", "한국어"), ("zh", "中文"),
    ]

    private func toggle(
        _ title: LocalizedStringKey, _ key: LaunchOptions.Key, isOn: Bool,
        stored: @escaping @Sendable (Bool) -> Bool = { $0 }, help: LocalizedStringKey
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { shown in
                let (id, value) = (targetID, stored(shown))
                apply { try await $0.setOption(id: id, key, to: value) }
            }
        )) {
            label(title, key, help: help)
        }
    }

    /// Le nom de l'option, son explication, et — si elle est reglee a ce niveau —
    /// une pastille et le bouton pour y renoncer.
    private func label(_ title: LocalizedStringKey, _ key: LaunchOptions.Key, help: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(title)
                if overridden.contains(key) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        .accessibilityLabel(scope == .game ? "Forcé pour ce jeu" : "Modifié")
                    Button {
                        let id = targetID
                        apply { try await $0.resetOptions(id: id, key) }
                    } label: {
                        Label(scope == .game ? "Suivre le réglage général" : "Revenir au réglage de Cidre",
                              systemImage: "arrow.uturn.backward")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(scope == .game
                        ? "Forcé pour ce jeu. Cliquer pour suivre à nouveau le réglage général."
                        : "Modifié par toi. Cliquer pour revenir au réglage de Cidre.")
                }
            }
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var threads: Binding<Int> {
        Binding(
            get: { options.compilerThreads },
            set: { value in
                let id = targetID
                apply { try await $0.setOption(id: id, .compilerThreads, to: value) }
            }
        )
    }
}

/// Les options de lancement dans la fiche d'un jeu : ce qu'on y change est
/// force pour ce jeu, par-dessus les reglages generaux.
struct LaunchOptionsSection: View {
    let game: Game
    @Binding var info: GameInfo?
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Section {
            if let info {
                LaunchOptionsEditor(
                    targetID: game.id, scope: .game,
                    options: info.options, overridden: info.overridden
                ) { change in
                    let id = game.id
                    Task {
                        let updated = await library.changeOptions(of: game, change)
                        // la selection a pu changer pendant l'ecriture
                        if game.id == id, let updated { self.info = updated }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Options de lancement")
        } footer: {
            Text("Ce jeu suit les réglages généraux (Réglages → Options), sauf ce que tu forces ici. S'applique au prochain lancement.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
