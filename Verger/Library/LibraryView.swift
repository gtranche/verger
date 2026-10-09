import CidreBridge
import SwiftUI
import UniformTypeIdentifiers

/// Le verger : la grille des jeux, et la fiche du jeu selectionne.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(AppUpdateModel.self) private var updater
    @Environment(\.openSettings) private var openSettings
    @State private var selection: Game.ID?
    @State private var installingFromSteam = false
    @State private var loggingIn = false
    @State private var reporting: ReportRequest?
    /// Le jeu dont on demande confirmation avant de forcer l'arret.
    @State private var stopping: Game?
    /// Un installeur vient d'etre lance : le jeu a ajouter est sans doute sur C:.
    @State private var ranInstaller = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)]

    var body: some View {
        @Bindable var library = library

        content
            .frame(minWidth: 620, minHeight: 440)
            .navigationTitle("Verger")
            .searchable(text: $library.search, prompt: "Rechercher un jeu")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filtre", selection: $library.filter) {
                        ForEach(LibraryModel.Filter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem {
                    Menu {
                        Button("Installer un jeu Steam…") { installingFromSteam = true }
                        Divider()
                        Button("Ajouter un jeu non-Steam…") { addLocalGame() }
                        Button("Lancer un installeur Windows…") { runInstaller() }
                        Divider()
                        Button("Connexion à Steam…") { loggingIn = true }
                    } label: {
                        Label("Ajouter un jeu", systemImage: "plus")
                    }
                    .disabled(library.cli == nil)
                }
                ToolbarItem {
                    SettingsLink {
                        Label("Réglages", systemImage: "gearshape")
                    }
                    .help("Réglages : Cidre, compte Steam, options générales, Verger")
                }
                ToolbarItem {
                    Button {
                        Task {
                            await library.reload()
                            await library.checkUpdates(refresh: true)
                        }
                    } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                }
            }
            .inspector(isPresented: inspectorShown) {
                if let game = selectedGame {
                    GameDetail(game: game)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
            }
            .sheet(isPresented: $installingFromSteam) {
                InstallSheet().environment(library)
            }
            .sheet(isPresented: $loggingIn) {
                LoginSheet().environment(library)
            }
            .sheet(item: $reporting) { ReportSheet(request: $0).environment(library) }
            .confirmationDialog(
                "Forcer l'arrêt de \(stoppingName) ?",
                isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                presenting: stopping
            ) { game in
                Button("Forcer l'arrêt", role: .destructive) { Task { await library.stop(game) } }
            } message: { _ in
                Text("Le jeu est arrêté sans prévenir : ce qui n'a pas été sauvegardé dans la partie est perdu. Tout ce que Cidre fait tourner s'arrête avec lui.")
            }
            .onChange(of: library.loginNeeded) { _, needed in
                guard needed else { return }
                library.loginNeeded = false
                // la fenetre « Installer un jeu Steam » propose deja la connexion
                if !installingFromSteam { loggingIn = true }
            }
            .alert("Une erreur est survenue", isPresented: errorShown) {
                Button("OK", role: .cancel) {}
                // le message s'efface a la fermeture de l'alerte : on le garde
                Button("Signaler…") { reporting = ReportRequest(error: library.lastError) }
            } message: {
                Text(library.lastError ?? "")
            }
            // Ce qui tourne en ce moment, y compris lance depuis Steam.
            .task {
                while !Task.isCancelled {
                    await library.refreshRunning()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            .task {
                await library.reload()
                // sans attendre le prochain tour de la boucle ci-dessus, qui a
                // demarre avant que Cidre ne soit localise
                await library.refreshRunning()
                // `Verger --jeu <id>` ouvre la fiche d'un jeu, `--connexion` la
                // connexion a Steam, `--reglages` les reglages
                let arguments = CommandLine.arguments
                if let flag = arguments.firstIndex(of: "--jeu"), arguments.indices.contains(flag + 1) {
                    selection = arguments[flag + 1]
                }
                if let flag = arguments.firstIndex(of: "--journal"), arguments.indices.contains(flag + 1) {
                    selection = arguments[flag + 1]
                }
                if arguments.contains("--connexion") { loggingIn = true }
                // `Verger --signaler <id>` prepare le rapport d'incident d'un jeu
                if let flag = arguments.firstIndex(of: "--signaler"), arguments.indices.contains(flag + 1),
                   let game = library.games.first(where: { $0.id == arguments[flag + 1] }) {
                    reporting = ReportRequest(game: game)
                }
                if arguments.contains("--reglages") { openSettings() }
                // le reste peut attendre : il interroge le reseau
                await library.checkRuntime()
                await library.checkUpdates()
                await updater.check()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch library.state {
        case .loading:
            ProgressView("Lecture de la bibliothèque…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cidreMissing:
            RuntimeMissingView(chooseCidre: chooseCidre)
        case let .failed(message):
            ContentUnavailableView {
                Label("Bibliothèque illisible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await library.reload() } }
                Button("Choisir la commande cidre…") { chooseCidre() }
            }
        case .loaded:
            if library.visibleGames.isEmpty {
                ContentUnavailableView {
                    Label(library.games.isEmpty ? "Aucun jeu installé" : "Aucun jeu ne correspond", systemImage: "leaf")
                } actions: {
                    if library.games.isEmpty {
                        Button("Installer un jeu Steam…") { installingFromSteam = true }
                        Button("Ajouter un jeu non-Steam…") { addLocalGame() }
                    }
                }
            } else {
                grid.safeAreaInset(edge: .top, spacing: 0) { RuntimeBanners() }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(library.visibleGames) { game in
                    // Un bouton, pas un simple geste : la carte reste activable au
                    // clavier et par VoiceOver. Double-clic = jouer.
                    Button {
                        selection = selection == game.id ? nil : game.id
                    } label: {
                        GameCard(
                            game: game,
                            isRunning: library.running.contains(game.id),
                            isSelected: selection == game.id,
                            download: game.appid.flatMap { library.downloads[$0] },
                            updateAvailable: game.appid.map { library.updates[$0] != nil } ?? false,
                            cancelDownload: { game.appid.map(library.cancelDownload) },
                            stop: game.launch == .cidre ? { stopping = game } : nil,
                            play: { library.play(game) }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(game.name)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if game.installed { library.play(game) }
                    })
                }
            }
            .padding(24)
        }
    }

    // MARK: Choix de fichiers

    private func chooseFile(title: String, message: String, types: [UTType], directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.string(title)
        panel.message = L10n.string(message)
        panel.prompt = L10n.string("Choisir")
        panel.allowedContentTypes = types
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if let directory { panel.directoryURL = directory }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseCidre() {
        guard let url = chooseFile(
            title: "Commande cidre", message: "Choisis la commande `cidre` de ton installation de Cidre.",
            types: [.item]) else { return }
        Task { await library.useCidre(at: url) }
    }

    private func addLocalGame() {
        Task {
            // Apres un installeur, le jeu est sur le disque C: du prefixe.
            let directory = ranInstaller ? await library.prefixDirectory() : nil
            guard let url = chooseFile(
                title: "Ajouter un jeu non-Steam",
                message: "Choisis l'exécutable (.exe) du jeu. Ses fichiers restent où ils sont.",
                types: [.exe], directory: directory) else { return }
            if let game = await library.addLocalGame(executable: url) {
                selection = game.id
                ranInstaller = false
            }
        }
    }

    private func runInstaller() {
        guard let url = chooseFile(
            title: "Lancer un installeur Windows",
            message: "Choisis l'installeur (.exe). Une fois le jeu installé, ajoute-le avec « Ajouter un jeu non-Steam… ».",
            types: [.exe]) else { return }
        ranInstaller = true
        library.runInstaller(url)
    }

    private var stoppingName: String { stopping?.name ?? "" }

    private var selectedGame: Game? {
        library.games.first { $0.id == selection }
    }

    private var inspectorShown: Binding<Bool> {
        Binding(get: { selectedGame != nil }, set: { if !$0 { selection = nil } })
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
    }
}
