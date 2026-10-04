import CidreBridge
import SwiftUI

/// La fiche d'un jeu (`cidre info --json`) : ou il vit, et ses options de
/// lancement actives. En lecture seule pour l'instant ; le panneau qui ecrit
/// profils.toml arrive avec la Phase 2.
struct GameDetail: View {
    let game: Game
    @Environment(LibraryModel.self) private var library

    @State private var info: GameInfo?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Plateforme") { PlatformBadge(game: game) }
                LabeledContent("Source", value: game.source == .cidre ? "Dossier Cidre" : "Client Steam")
                LabeledContent("Taille", value: game.sizeBytes.formatted(.byteCount(style: .file)))
                LabeledContent("Dernier lancement") {
                    if let date = game.lastPlayed {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("Jamais").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("AppID", value: String(game.appid))
                if let info {
                    LabeledContent("Sauvegardes iCloud", value: info.savesSynced ? "Synchronisées" : "Non configurées")
                }
            } header: {
                Text(game.name).font(.title3.weight(.semibold))
            }

            Section("Options de lancement") {
                if let options = info?.options {
                    if game.launch == .native {
                        Text("Jeu natif : lancé par Steam, sans la pile Cidre.")
                            .foregroundStyle(.secondary)
                    } else {
                        OptionRow("Ordre mémoire strict (TSO)", on: options.tso)
                        OptionRow("Vsync", on: options.vsync)
                        OptionRow("HUD fps / GPU", on: options.hud)
                        OptionRow("Shaders en fond (async)", on: options.asyncShaders)
                        if options.compilerThreads > 0 {
                            LabeledContent("Fils compilateurs", value: String(options.compilerThreads))
                        }
                        OptionRow("Anti-triche permissif (Modded)", on: options.eacUntrusted)
                        OptionRow("Correctif LuaJIT", on: options.luajit)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            Section {
                Button {
                    library.play(game)
                } label: {
                    Label(library.running.contains(game.appid) ? "En cours…" : "Jouer", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!game.installed || library.running.contains(game.appid))

                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: game.path)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .task(id: game.appid) {
            info = nil
            error = nil
            do {
                info = try await library.info(for: game)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct OptionRow: View {
    let title: String
    let on: Bool

    init(_ title: String, on: Bool) {
        self.title = title
        self.on = on
    }

    var body: some View {
        LabeledContent(title) {
            Text(on ? "Activé" : "Désactivé")
                .foregroundStyle(on ? .primary : .secondary)
        }
    }
}
