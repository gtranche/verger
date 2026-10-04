import CidreBridge
import SwiftUI

/// La fiche d'un jeu (`cidre info --json`) : ou il vit, ses options de
/// lancement, et ce qu'on peut en faire (jouer, desinstaller).
struct GameDetail: View {
    let game: Game
    @Environment(LibraryModel.self) private var library

    @State private var info: GameInfo?
    @State private var error: String?
    @State private var confirmingUninstall = false

    private var sourceLabel: String {
        switch game.source {
        case .steam: "Client Steam"
        case .cidre: "Dossier Cidre"
        case .local: "Hors Steam"
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Plateforme") { PlatformBadge(game: game) }
                LabeledContent("Source", value: sourceLabel)
                if game.sizeBytes > 0 {
                    LabeledContent("Taille", value: game.sizeBytes.formatted(.byteCount(style: .file)))
                }
                LabeledContent("Dernier lancement") {
                    if let date = game.lastPlayed {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("Jamais").foregroundStyle(.secondary)
                    }
                }
                if let appid = game.appid {
                    LabeledContent("AppID", value: String(appid))
                }
                if let info {
                    LabeledContent("Sauvegardes iCloud", value: info.savesSynced ? "Synchronisées" : "Non configurées")
                }
            } header: {
                Text(game.name).font(.title3.weight(.semibold))
            }

            if game.launch == .native {
                Section("Options de lancement") {
                    Text("Jeu natif : lancé par Steam, sans la pile Cidre.")
                        .foregroundStyle(.secondary)
                }
            } else if let error {
                Section("Options de lancement") {
                    Text(error).foregroundStyle(.red)
                }
            } else {
                LaunchOptionsSection(game: game, info: $info)
            }

            Section {
                if let appid = game.appid, let progress = library.downloads[appid] {
                    DownloadStatus(progress: progress) { library.cancelDownload(appid: appid) }
                } else if let appid = game.appid, game.source == .cidre, !game.installed {
                    Button {
                        library.download(appid: appid)
                    } label: {
                        Label("Reprendre le téléchargement", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        library.play(game)
                    } label: {
                        Label(library.running.contains(game.id) ? "En cours…" : "Jouer", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!game.installed || library.running.contains(game.id))
                }

                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: game.path)
                }
                .frame(maxWidth: .infinity)

                switch game.source {
                case .local:
                    Button("Retirer de la bibliothèque") {
                        Task { await library.remove(game) }
                    }
                    .frame(maxWidth: .infinity)
                    .help("Le jeu quitte Verger ; ses fichiers ne sont pas touchés.")
                case .cidre:
                    Button("Désinstaller…", role: .destructive) { confirmingUninstall = true }
                        .frame(maxWidth: .infinity)
                        .disabled(game.appid.map { library.downloads[$0] != nil } ?? false)
                case .steam:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Désinstaller \(game.name) ?", isPresented: $confirmingUninstall
        ) {
            Button("Désinstaller", role: .destructive) {
                Task { await library.remove(game) }
            }
        } message: {
            Text("Ses fichiers (\(game.sizeBytes.formatted(.byteCount(style: .file)))) seront supprimés du disque. Tu pourras le réinstaller depuis tes jeux Steam.")
        }
        .task(id: game.id) {
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
