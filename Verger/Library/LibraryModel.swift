import AppKit
import CidreBridge
import Foundation
import Observation

/// L'etat de la bibliotheque : la liste que rend `cidre list --json`, les jeux
/// en cours de lancement, et les telechargements.
@MainActor
@Observable
final class LibraryModel {
    enum State: Equatable {
        case loading
        /// Aucune CLI `cidre` trouvee : Cidre n'est pas installe, ou ailleurs.
        case cidreMissing
        case loaded
        case failed(String)
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tous", native = "Natifs", cidre = "Cidre"
        var id: Self { self }
    }

    /// Les jeux que possede le compte Steam (`cidre library --json`).
    enum OwnedState: Equatable {
        case idle, loading, loaded
        /// SteamCMD n'a pas de session : il faut un `cidre login` au Terminal.
        case sessionMissing
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var games: [Game] = []
    /// Jeux dont `cidre play` n'a pas encore rendu la main.
    private(set) var running: Set<String> = []
    var lastError: String?
    var filter: Filter = .all
    var search = ""

    private(set) var ownedState: OwnedState = .idle
    private(set) var owned: [OwnedGame] = []
    /// Telechargements en cours, par appid.
    private(set) var downloads: [Int: DownloadProgress] = [:]
    private var downloadTasks: [Int: Task<Void, Never>] = [:]

    /// L'etat du runtime Cidre (`cidre status`), et la release plus recente s'il y en a une.
    private(set) var runtimeStatus: RuntimeStatus?
    private(set) var availableUpdate: RuntimeRelease?
    /// Non nul pendant une installation ou une mise a jour de Cidre.
    private(set) var runtimeStep: RuntimeInstaller.Step?
    private var runtimeTask: Task<Void, Never>?

    /// Chemin de la CLI choisi a la main (sinon detection automatique).
    var cidrePath: String? = UserDefaults.standard.string(forKey: "cidrePath") {
        didSet { UserDefaults.standard.set(cidrePath, forKey: "cidrePath") }
    }

    /// Le compte Steam avec lequel l'utilisateur s'est connecte dans Verger.
    /// Sans lui, Cidre prend celui que le client Steam a memorise.
    var steamUser: String? = UserDefaults.standard.string(forKey: "steamUser") {
        didSet {
            UserDefaults.standard.set(steamUser, forKey: "steamUser")
            cli?.steamUser = steamUser
        }
    }

    private(set) var cli: CidreCLI?

    var visibleGames: [Game] {
        games
            .filter { game in
                switch filter {
                case .all: true
                case .native: game.launch == .native
                case .cidre: game.launch == .cidre
                }
            }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Bibliotheque

    func reload() async {
        guard var cli = CidreCLI.locate(userChoice: cidrePath) else {
            self.cli = nil
            state = .cidreMissing
            return
        }
        cli.steamUser = steamUser
        self.cli = cli
        if games.isEmpty { state = .loading }
        do {
            games = try await cli.list()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func useCidre(at url: URL) async {
        cidrePath = url.path
        await reload()
    }

    func info(for game: Game) async throws -> GameInfo? {
        try await cli?.info(id: game.id)
    }

    /// Applique un changement d'options (`cidre set` / `cidre unset`) et rend la
    /// fiche a jour, telle que Cidre la resout apres coup.
    func changeOptions(of game: Game, _ change: @escaping @Sendable (CidreCLI) async throws -> Void) async -> GameInfo? {
        guard let cli else { return nil }
        do {
            try await change(cli)
        } catch {
            lastError = error.localizedDescription
        }
        return try? await cli.info(id: game.id)
    }

    func play(_ game: Game) {
        guard let cli, !running.contains(game.id) else { return }
        running.insert(game.id)
        let log = Self.logsDirectory.appendingPathComponent("play-\(game.id).log")
        Task {
            do {
                try await cli.play(id: game.id, log: log)
            } catch {
                lastError = error.localizedDescription
            }
            running.remove(game.id)
            // Le jeu a tourne : sa date de dernier lancement a pu changer.
            await reload()
        }
    }

    /// Retire un jeu hors Steam, ou desinstalle un jeu du dossier Cidre.
    func remove(_ game: Game) async {
        guard let cli else { return }
        do {
            try await cli.remove(id: game.id)
        } catch {
            lastError = error.localizedDescription
        }
        await reload()
        if ownedState == .loaded { await loadOwned() }
    }

    // MARK: Runtime Cidre

    /// Lit l'etat du runtime et regarde si une version plus recente est publiee.
    /// Un depot de developpement (version « dev ») ne se met pas a jour par Verger.
    func checkRuntime() async {
        guard let cli else {
            runtimeStatus = nil
            return
        }
        // une CLI d'avant `cidre status` : pas d'etat, pas de mise a jour proposee
        guard let status = try? await cli.status() else { return }
        runtimeStatus = status
        guard !status.isDevelopmentCheckout,
              let latest = try? await RuntimeInstaller.latestRelease() else {
            availableUpdate = nil
            return
        }
        availableUpdate = latest.isNewer(than: status.version) ? latest : nil
    }

    /// Installe Cidre, ou le met a jour : telechargement, decompression, puis
    /// `cidre setup`. Les jeux, les sauvegardes et les reglages restent en place.
    func installRuntime() {
        guard runtimeTask == nil else { return }
        runtimeStep = .downloading(doneBytes: 0, totalBytes: availableUpdate?.sizeBytes ?? 0)
        runtimeTask = Task {
            do {
                let release = if let availableUpdate { availableUpdate } else { try await RuntimeInstaller.latestRelease() }
                _ = try await RuntimeInstaller().install(release) { step in
                    Task { @MainActor in
                        // une etape arrivee apres la fin ne doit pas la ressusciter
                        if self.runtimeStep != nil { self.runtimeStep = step }
                    }
                }
                availableUpdate = nil
            } catch is CancellationError {
                // arrete par l'utilisateur
            } catch {
                lastError = error.localizedDescription
            }
            runtimeStep = nil
            runtimeTask = nil
            await reload()
            await checkRuntime()
        }
    }

    func cancelRuntimeInstall() {
        runtimeTask?.cancel()
    }

    // MARK: Jeux Steam du compte

    func loadOwned(refresh: Bool = false) async {
        guard let cli else { return }
        if owned.isEmpty || refresh { ownedState = .loading }
        do {
            owned = try await cli.library(refresh: refresh)
            ownedState = .loaded
        } catch CidreError.steamSessionMissing {
            ownedState = .sessionMissing
        } catch {
            ownedState = .failed(error.localizedDescription)
        }
    }

    /// Telecharge la version Windows dans le dossier Cidre (`cidre dl`).
    func download(appid: Int) {
        guard let cli, downloadTasks[appid] == nil else { return }
        downloads[appid] = DownloadProgress()
        downloadTasks[appid] = Task {
            do {
                try await cli.download(appid: appid) { progress in
                    Task { @MainActor in
                        // un avancement arrive apres la fin ne doit pas la ressusciter
                        if self.downloads[appid] != nil { self.downloads[appid] = progress }
                    }
                }
            } catch is CancellationError {
                // arrete par l'utilisateur : SteamCMD reprendra ou il en etait
            } catch CidreError.steamSessionMissing {
                ownedState = .sessionMissing
                lastError = CidreError.steamSessionMissing.localizedDescription
            } catch {
                lastError = error.localizedDescription
            }
            downloads[appid] = nil
            downloadTasks[appid] = nil
            await reload()
            if ownedState == .loaded { await loadOwned() }
        }
        // le dossier du jeu apparait des le debut : on le montre dans la grille
        Task {
            try? await Task.sleep(for: .seconds(3))
            await reload()
        }
    }

    func cancelDownload(appid: Int) {
        downloadTasks[appid]?.cancel()
    }

    /// Version macOS : c'est le client Steam qui l'installe, dans sa propre
    /// bibliotheque. On lui ouvre sa fenetre d'installation.
    func installNative(appid: Int) {
        if let url = URL(string: "steam://install/\(appid)") { NSWorkspace.shared.open(url) }
    }

    // MARK: Jeux hors Steam

    /// Ajoute un .exe a la bibliotheque (`cidre add`) ; rend le jeu cree.
    @discardableResult
    func addLocalGame(executable: URL) async -> Game? {
        guard let cli else { return nil }
        do {
            let game = try await cli.add(executable: executable)
            await reload()
            return game
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Lance un installeur Windows par la pile Cidre (`cidre run`), sans l'ajouter.
    func runInstaller(_ executable: URL) {
        guard let cli else { return }
        let log = Self.logsDirectory.appendingPathComponent("run-\(executable.deletingPathExtension().lastPathComponent).log")
        Task {
            do {
                try await cli.runExecutable(executable, log: log)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Le disque C: du prefixe : la ou un installeur a depose son jeu.
    func prefixDirectory() async -> URL? {
        try? await cli?.prefix()
    }

    static let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Verger")
}
