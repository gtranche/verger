import CidreBridge
import SwiftUI
import UniformTypeIdentifiers

/// La fiche d'un jeu (`cidre info --json`) : ou il vit, ses options de
/// lancement, et ce qu'on peut en faire (jouer, desinstaller).
struct GameDetail: View {
    let game: Game
    @Environment(LibraryModel.self) private var library

    @State private var info: GameInfo?
    @State private var error: String?
    @State private var confirmingUninstall = false
    @State private var searchingCover = false
    private var covers: CoverStore { CoverStore.shared }

    private var sourceLabel: String {
        switch game.source {
        case .steam: L10n.string("Client Steam")
        case .cidre: L10n.string("Dossier Cidre")
        case .local: L10n.string("Hors Steam")
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Plateforme") { PlatformBadge(game: game) }
                LabeledContent("Source", value: sourceLabel)
                if game.sizeBytes > 0 {
                    LabeledContent("Taille", value: L10n.bytes(game.sizeBytes))
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
                // Un jeu natif garde ses sauvegardes par Steam Cloud ; un jeu
                // Windows compte sur la copie de Cidre.
                SavesSection(game: game)
                LaunchOptionsSection(game: game, info: $info)
            }

            Section {
                if let appid = game.appid, library.downloads[appid] == nil, library.updates[appid] != nil {
                    // Un jeu du dossier Cidre, c'est Cidre qui le met a jour ; un
                    // jeu du client Steam, c'est Steam.
                    if game.source == .cidre {
                        Button {
                            library.download(appid: appid)
                        } label: {
                            Label("Mettre à jour", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(library.running.contains(game.id))
                    } else {
                        Label("Une mise à jour est disponible : Steam l'installe.", systemImage: "arrow.down.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Button("Ouvrir les téléchargements de Steam") { library.openSteamDownloads() }
                            .frame(maxWidth: .infinity)
                    }
                }
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

                Menu("Jaquette") {
                    Button("Choisir une image…") { chooseCoverFile() }
                    Button("Chercher sur SteamGridDB…") { searchingCover = true }
                    if covers.customCover(for: game.id) != nil {
                        Divider()
                        Button("Rétablir la jaquette d'origine") { covers.removeCover(for: game.id) }
                    }
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
                    Button("Désinstaller…", role: .destructive) { confirmingUninstall = true }
                        .frame(maxWidth: .infinity)
                        .disabled(library.running.contains(game.id))
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $searchingCover) { CoverPicker(game: game) }
        .confirmationDialog(
            "Désinstaller \(game.name) ?", isPresented: $confirmingUninstall
        ) {
            if game.source == .steam {
                Button("Désinstaller avec Steam", role: .destructive) { library.uninstallFromSteam(game) }
            } else {
                Button("Désinstaller", role: .destructive) {
                    Task { await library.remove(game) }
                }
            }
        } message: {
            if game.source == .steam {
                Text("Ce jeu est dans la bibliothèque du client Steam : Steam va s'ouvrir et te demander de confirmer. Ses fichiers (\(L10n.bytes(game.sizeBytes))) seront supprimés ; tu pourras le réinstaller depuis tes jeux Steam.")
            } else {
                Text("Ses fichiers (\(L10n.bytes(game.sizeBytes))) seront supprimés du disque. Tu pourras le réinstaller depuis tes jeux Steam.")
            }
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

    private func chooseCoverFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choisir une jaquette")
        panel.message = L10n.string("Choisis une image au format portrait (600 × 900 idéalement).")
        panel.prompt = L10n.string("Choisir")
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try covers.setCover(for: game.id, from: url)
        } catch {
            library.lastError = L10n.string("Cette image est illisible.")
        }
    }
}
