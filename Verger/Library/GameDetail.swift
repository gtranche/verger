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
    @State private var reporting: ReportRequest?
    @State private var sharing = false
    @State private var sendingDiagnostic = false
    @State private var showingLog = false
    @State private var confirmingStop = false
    private var covers: CoverStore { CoverStore.shared }
    /// Le journal demande au lancement de Verger ne s'ouvre qu'une fois.
    @MainActor private static var openedLogFromArguments = false

    private var sourceLabel: String {
        switch game.source {
        case .steam: L10n.string("Client Steam")
        case .cidre: L10n.string("Dossier Cidre")
        case .local: L10n.string("Hors Steam")
        case .battlenet: L10n.string("Battle.net")
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Plateforme") { PlatformBadge(game: game) }
                LabeledContent("Source", value: sourceLabel)
                // un jeu Cidre vit sur un disque : ce Mac, ou un disque externe ;
                // il se deplace d'ici, comme sur une console
                if game.source == .cidre, let name = library.locationName(of: game) {
                    LabeledContent("Disque") {
                        HStack(spacing: 8) {
                            if game.online {
                                Text(verbatim: name)
                            } else {
                                Label(L10n.format("%@ (débranché)", name), systemImage: "externaldrive.badge.xmark")
                                    .foregroundStyle(.orange)
                            }
                            if game.installed || !game.online, library.locationsSupported == true {
                                MoveMenu(game: game, compact: true)
                            }
                        }
                    }
                }
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
                if let shaders = info?.shaders {
                    LabeledContent("Shaders") {
                        Text(verbatim: shaders.summary)
                            .help(L10n.string("Au premier lancement d'un jeu, ses shaders sont compilés pour ce Mac : quelques minutes d'écran noir ou de textures manquantes, une fois. Ils sont à refaire après une mise à jour de macOS."))
                    }
                }
            } header: {
                Text(game.name).font(.title3.weight(.semibold))
            }

            // Jouer, arreter, mettre a jour : sous la main, avant les reglages.
            Section {
                let update = game.appid.flatMap { library.updates[$0] }
                let isRunning = library.running.contains(game.id)
                let move = library.moveStatus(of: game)
                if let appid = game.appid, let progress = library.downloads[appid] {
                    DownloadStatus(progress: progress) { library.cancelDownload(appid: appid) }
                } else if let move, move.isRunning {
                    MoveProgress(status: move) { library.stopMove(game) }
                } else if !game.online {
                    // son disque est debranche : rien n'est perdu, il revient au rebranchement
                    Button {} label: {
                        Label("Jouer", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                    notice(library.offlineMessage(for: game), icon: "externaldrive.badge.xmark")
                } else if let appid = game.appid, game.needsWindowsVersion {
                    // Version macOS 32 bits du client Steam : macOS ne la lance
                    // plus. Cidre installe la version Windows a cote.
                    Button {
                        library.download(appid: appid)
                    } label: {
                        Label("Installer la version Windows", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    notice(Game.mac32BitNotice, icon: "exclamationmark.triangle")
                } else if let appid = game.appid, game.source == .cidre, !game.installed {
                    Button {
                        library.download(appid: appid)
                    } label: {
                        Label("Reprendre le téléchargement", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if let appid = game.appid, let update, !isRunning, library.playPlan(for: game) == .updateThenPlay {
                    // Une version plus recente est publiee : « Jouer » l'installe
                    // d'abord. Jouer tout de suite reste possible, a cote.
                    Button {
                        library.play(game)
                    } label: {
                        Label("Mettre à jour et jouer", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("Build installé : \(String(update.installedBuild)) · publié : \(String(update.availableBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    // la derniere tentative a echoue : pourquoi, et quoi faire
                    if library.updateNotices[appid] == nil, update.status?.state == .failed,
                       let explanation = update.status?.explanation {
                        notice(explanation)
                    }
                    Button("Jouer sans mettre à jour") { library.play(game, skipUpdate: true) }
                        .frame(maxWidth: .infinity)
                        .help("Lance la version installée. La mise à jour sera proposée à nouveau au prochain lancement.")
                    Button("Mettre à jour sans jouer") { library.download(appid: appid) }
                        .frame(maxWidth: .infinity)
                } else if game.source == .battlenet {
                    // `cidre play bnet-...` : Cidre ouvre le client connecte avec les
                    // reglages de la fiche du jeu, et c'est lui qui lance le jeu.
                    Button {
                        library.play(game)
                    } label: {
                        Label(isRunning ? "En cours…" : "Jouer", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!game.playable || isRunning)
                    Button("Ouvrir Battle.net") { library.openBattleNet() }
                        .frame(maxWidth: .infinity)
                        .disabled(isRunning || library.openingBattleNet)
                    Text("Cidre lance le jeu par le client Battle.net, connecté, avec les réglages de sa fiche. Ouvre le client pour installer ou mettre à jour un jeu ; « Jouer » dans le client le lancerait sans ces réglages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button {
                        library.play(game)
                    } label: {
                        Label(isRunning ? "En cours…" : "Jouer", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!game.playable || isRunning)

                    // Une mise a jour connue que « Jouer » n'installe pas : un jeu
                    // du dossier Cidre dont l'option est coupee (ou epingle sur une
                    // branche), ou un jeu du client Steam, que Steam met a jour.
                    if let appid = game.appid, let update {
                        if game.source == .cidre {
                            notice(update.status?.explanation ?? L10n.string("Une mise à jour est disponible."))
                            // (un jeu epingle sur une branche beta : la branche publique n'est pas la sienne)
                            if update.status?.reason != .branch {
                                Button("Mettre à jour") { library.download(appid: appid) }
                                    .frame(maxWidth: .infinity)
                                    .disabled(isRunning)
                            }
                        } else {
                            notice(L10n.string("Une mise à jour est disponible : Steam l'installe."))
                            Button("Ouvrir les téléchargements de Steam") { library.openSteamDownloads() }
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                // la mise a jour d'avant lancement n'a pas pu se faire : pourquoi
                if let appid = game.appid, let text = library.updateNotices[appid] {
                    notice(text)
                }
                // un deplacement interrompu ou en echec : l'original est intact
                if let move, move.isUnfinished, game.online {
                    notice(move.explanation ?? "", icon: "externaldrive.badge.exclamationmark")
                    Button("Reprendre le déplacement") { library.resumeMove(game) }
                        .frame(maxWidth: .infinity)
                        .disabled(isRunning)
                    Button("Abandonner le déplacement") { Task { await library.abandonMove(game) } }
                        .frame(maxWidth: .infinity)
                        .help("Efface la copie entamée ; le jeu reste où il est.")
                }
                // premier lancement, ou cache a refaire : la compilation des shaders
                if let text = library.shaderNotices[game.id] {
                    notice(text, icon: "hourglass")
                }

                // Un jeu lance par Cidre qui ne repond plus, ou dont la fenetre
                // n'est jamais apparue : on peut le forcer a s'arreter.
                if game.launch == .cidre, library.running.contains(game.id) {
                    Button("Forcer l'arrêt…", role: .destructive) { confirmingStop = true }
                        .frame(maxWidth: .infinity)
                        .confirmationDialog("Forcer l'arrêt de \(game.name) ?", isPresented: $confirmingStop) {
                            Button("Forcer l'arrêt", role: .destructive) {
                                Task { await library.stop(game) }
                            }
                        } message: {
                            Text("Le jeu est arrêté sans prévenir : ce qui n'a pas été sauvegardé dans la partie est perdu. Tout ce que Cidre fait tourner s'arrête avec lui.")
                        }
                }
            }

            // ce que la base de profils de Cidre dit du jeu, pour ce Mac
            if game.launch != .native, let compatibility = info?.compatibility {
                CompatibilitySection(compatibility: compatibility)
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
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: game.path)
                }
                .frame(maxWidth: .infinity)
                .disabled(!game.online)

                if game.launch == .cidre {
                    Button("Afficher le journal…") { showingLog = true }
                        .frame(maxWidth: .infinity)
                }

                Button("Signaler un problème…") { reporting = ReportRequest(game: game) }
                    .frame(maxWidth: .infinity)

                if game.launch == .cidre {
                    Button("Envoyer un diagnostic…") { sendingDiagnostic = true }
                        .frame(maxWidth: .infinity)
                        .help("Envoie à l'équipe de Cidre de quoi comprendre un problème, et reçois un code à lui donner.")
                }

                if game.launch == .cidre {
                    Button("Partager mon résultat…") { sharing = true }
                        .frame(maxWidth: .infinity)
                        .help("Dis comment le jeu tourne sur ton Mac : ton rapport nourrit la fiche du jeu.")
                }

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
                        .disabled((game.appid.map { library.downloads[$0] != nil } ?? false)
                            || !game.online || library.moveStatus(of: game)?.isRunning == true)
                case .steam:
                    Button("Désinstaller…", role: .destructive) { confirmingUninstall = true }
                        .frame(maxWidth: .infinity)
                        .disabled(library.running.contains(game.id))
                case .battlenet:
                    // Battle.net installe, met a jour et desinstalle ses jeux
                    // lui-meme : le bouton du haut ouvre deja le client.
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $searchingCover) { CoverPicker(game: game) }
        .sheet(item: $reporting) { ReportSheet(request: $0).environment(library) }
        .sheet(isPresented: $sharing) { GameReportSheet(game: game).environment(library) }
        .sheet(isPresented: $sendingDiagnostic) { DiagnosticSendSheet(game: game).environment(library) }
        .sheet(isPresented: $showingLog) { LogSheet(game: game).environment(library) }
        .onAppear {
            // `Verger --journal <id>` ouvre le journal du jeu
            let arguments = CommandLine.arguments
            if let flag = arguments.firstIndex(of: "--journal"), arguments.indices.contains(flag + 1),
               arguments[flag + 1] == game.id, !Self.openedLogFromArguments {
                Self.openedLogFromArguments = true
                showingLog = true
            }
        }
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
        // une partie finie : l'etat des shaders (et la date) a change
        .onChange(of: library.running.contains(game.id)) { _, isRunning in
            guard !isRunning else { return }
            Task { if let fresh = try? await library.info(for: game) { info = fresh } }
        }
    }

    /// Une remarque sur la mise a jour du jeu (ou ses shaders), sous le bouton.
    private func notice(_ text: String, icon: String = "arrow.down.circle") -> some View {
        Label {
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .font(.callout)
        .foregroundStyle(.orange)
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
