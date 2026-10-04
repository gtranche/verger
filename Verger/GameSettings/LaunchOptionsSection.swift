import CidreBridge
import SwiftUI

/// Les options de lancement d'un jeu lance par Cidre : des interrupteurs qui
/// ecrivent le profils.toml de l'utilisateur (`cidre set`). Cidre livre ses
/// propres reglages par jeu ; ce qu'on change ici les surcharge, et
/// « Rétablir » y revient.
struct LaunchOptionsSection: View {
    let game: Game
    @Binding var info: GameInfo?
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Section {
            if let info {
                let options = info.options
                // L'interrupteur dit ce que le joueur gagne ; Cidre stocke l'inverse
                // (tso = true : ordre memoire strict).
                toggle("Performance CPU", .tso, isOn: !options.tso, stored: { !$0 },
                       help: "Relâche l'ordre mémoire émulé : gros gain CPU, mais certains jeux peuvent planter.")
                toggle("Vsync", .vsync, isOn: options.vsync,
                       help: "Désactivée : plus de plafond à 40 ou 30 fps, au prix d'un déchirement possible de l'image.")
                toggle("Compteur fps et charge GPU", .hud, isOn: options.hud,
                       help: "Affiche les performances à l'écran, pour voir l'effet d'un réglage.")
                toggle("Shaders compilés en fond", .asyncShaders, isOn: options.asyncShaders,
                       help: "Supprime les saccades quand le jeu découvre de nouveaux effets.")
                Picker(selection: threads(options.compilerThreads)) {
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

                if !info.overridden.isEmpty {
                    Button("Rétablir les réglages de Cidre") {
                        apply { try await $0.resetOptions(id: game.id) }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Options de lancement")
        } footer: {
            Text("S'applique au prochain lancement du jeu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(
        _ title: String, _ key: LaunchOptions.Key, isOn: Bool,
        stored: @escaping @Sendable (Bool) -> Bool = { $0 }, help: String
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { shown in
                let value = stored(shown)
                apply { try await $0.setOption(id: game.id, key, to: value) }
            }
        )) {
            label(title, key, help: help)
        }
    }

    /// Le nom de l'option, son explication, et une pastille si le joueur l'a
    /// lui-meme reglee (elle differe alors peut-etre du reglage de Cidre).
    private func label(_ title: String, _ key: LaunchOptions.Key, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(title)
                if info?.overridden.contains(key) == true {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        .help("Réglé par toi")
                        .accessibilityLabel("Réglé par toi")
                }
            }
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func threads(_ current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { value in apply { try await $0.setOption(id: game.id, .compilerThreads, to: value) } }
        )
    }

    private func apply(_ change: @escaping @Sendable (CidreCLI) async throws -> Void) {
        let id = game.id
        Task {
            let updated = await library.changeOptions(of: game, change)
            // la selection a pu changer pendant l'ecriture
            if game.id == id, let updated { info = updated }
        }
    }
}
