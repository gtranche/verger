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

    enum Filter: CaseIterable, Identifiable {
        case all, native, cidre
        var id: Self { self }

        var title: String {
            switch self {
            case .all: L10n.string("Tous")
            case .native: L10n.string("Natifs")
            case .cidre: "Cidre"
            }
        }
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
    private var launched: Set<String> = []
    /// Jeux que Cidre dit en cours (`cidre running`) : lances par Steam, par
    /// Verger ou au Terminal.
    private var reported: Set<String> = []
    /// Les jeux en cours, d'ou qu'ils aient ete lances.
    var running: Set<String> { launched.union(reported) }
    /// Depuis quand chaque jeu en cours tourne (le moment ou Verger l'a vu).
    private var runningSince: [String: Date] = [:]

    /// Afficher le jeu en cours dans le profil Discord.
    var discordEnabled = UserDefaults.standard.bool(forKey: "discord") {
        didSet {
            UserDefaults.standard.set(discordEnabled, forKey: "discord")
            Task { await updateDiscord() }
        }
    }
    private var discord: DiscordPresence?
    private var discordShown: (id: String, at: Date)?
    var lastError: String?
    /// Une action vient d'echouer faute de session Steam : il faut ouvrir la connexion.
    var loginNeeded = false
    var filter: Filter = .all
    var search = ""

    /// Le compte Steam et l'etat de sa session ; `nil` tant qu'on ne l'a pas demande.
    private(set) var steamSession: SteamSession?
    private(set) var checkingSession = false

    private(set) var ownedState: OwnedState = .idle
    private(set) var owned: [OwnedGame] = []
    /// Les jeux Steam installes dont une version plus recente est publiee, par appid.
    private(set) var updates: [Int: GameUpdate] = [:]
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
        launched.insert(game.id)
        let log = Self.logsDirectory.appendingPathComponent("play-\(game.id).log")
        Task {
            await refreshRunning()
            do {
                try await cli.play(id: game.id, log: log)
            } catch {
                lastError = error.localizedDescription
            }
            // Un jeu du client Steam : `cidre play` rend la main tout de suite,
            // et Steam met quelques secondes a le demarrer. On le garde « en
            // cours » le temps que Cidre le voie tourner.
            if game.source == .steam {
                for _ in 0..<10 where !reported.contains(game.id) {
                    try? await Task.sleep(for: .seconds(2))
                    await refreshRunning()
                }
            }
            launched.remove(game.id)
            await refreshRunning()
            // Le jeu a tourne : sa date de dernier lancement a pu changer.
            await reload()
        }
    }

    // MARK: Jeux en cours, et Discord

    /// Demande a Cidre ce qui tourne, et met Discord a jour. Appelee toutes les
    /// quelques secondes tant que la fenetre est ouverte.
    func refreshRunning() async {
        // un Cidre d'avant `cidre running` : on ne sait que ce qu'on a lance
        if let ids = try? await cli?.running() { reported = Set(ids) }
        let now = Date()
        for id in running where runningSince[id] == nil { runningSince[id] = now }
        runningSince = runningSince.filter { running.contains($0.key) }
        await updateDiscord()
    }

    /// Les jeux que Discord connait ; charge quand l'option est activee.
    private var discordCatalog: DiscordCatalog?
    private var loadingDiscordCatalog = false

    private static let discordCatalogCache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Verger/discord-jeux.json")

    private func updateDiscord() async {
        guard discordEnabled else {
            await stopDiscord()
            return
        }
        if discordCatalog == nil {
            // un seul chargement a la fois : la liste pese 13 Mo
            guard !loadingDiscordCatalog else { return }
            loadingDiscordCatalog = true
            discordCatalog = await DiscordCatalog.load(cache: Self.discordCatalogCache)
            loadingDiscordCatalog = false
        }
        // Le jeu a annoncer : le dernier demarre, parmi ceux que Discord connait.
        let candidates = games
            .filter { running.contains($0.id) }
            .sorted { (runningSince[$0.id] ?? .distantPast) > (runningSince[$1.id] ?? .distantPast) }
        var current: (game: Game, application: String)?
        for game in candidates {
            if let application = discordCatalog?.applicationID(name: game.name, steamAppID: game.appid) {
                current = (game, application)
                break
            }
        }
        guard let current else {
            await stopDiscord()
            return
        }
        // Deja annonce : on le redit une fois par minute, pour retrouver un
        // Discord qui aurait ete relance entre-temps.
        if let shown = discordShown, shown.id == current.game.id, Date().timeIntervalSince(shown.at) < 60 { return }
        // On se presente a Discord sous l'identite du jeu : un autre jeu, une
        // autre connexion.
        if discordShown?.id != current.game.id {
            await discord?.clear()
            discord = DiscordPresence(applicationID: current.application)
        }
        do {
            try await discord?.show(since: runningSince[current.game.id] ?? Date())
            discordShown = (current.game.id, Date())
        } catch {
            // Discord est ferme, ou refuse : on reessaiera au prochain tour.
            discordShown = nil
        }
    }

    private func stopDiscord() async {
        guard discordShown != nil || discord != nil else { return }
        await discord?.clear()
        discord = nil
        discordShown = nil
    }

    /// Un jeu du client Steam appartient a sa bibliotheque : c'est Steam qui le
    /// desinstalle, apres avoir demande confirmation dans sa propre fenetre.
    func uninstallFromSteam(_ game: Game) {
        guard let appid = game.appid, let url = URL(string: "steam://uninstall/\(appid)") else { return }
        NSWorkspace.shared.open(url)
        // Steam prend son temps : on relit la bibliotheque a plusieurs reprises.
        Task {
            for delay in [5, 15, 40] {
                try? await Task.sleep(for: .seconds(delay))
                await reload()
            }
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

    // MARK: Reglages generaux

    func defaultOptions() async -> DefaultOptions? {
        try? await cli?.defaultOptions()
    }

    /// Applique un changement aux reglages generaux et les rend a jour.
    func changeDefaultOptions(_ change: @escaping @Sendable (CidreCLI) async throws -> Void) async -> DefaultOptions? {
        guard let cli else { return nil }
        do {
            try await change(cli)
        } catch {
            lastError = error.localizedDescription
        }
        return try? await cli.defaultOptions()
    }

    // MARK: Session Steam

    /// Demande a Cidre si la session Steam est memorisee (`cidre session`).
    func checkSession() async {
        guard let cli else { return }
        checkingSession = true
        defer { checkingSession = false }
        steamSession = try? await cli.session()
        if steamSession?.connected == true, ownedState == .sessionMissing { ownedState = .idle }
    }

    /// Oublie la session Steam. Les jeux installes restent jouables ; il faudra
    /// se reconnecter pour installer ou mettre a jour.
    func logout() async {
        guard let cli else { return }
        do {
            try await cli.logout()
        } catch {
            lastError = error.localizedDescription
        }
        owned = []
        ownedState = .idle
        await checkSession()
    }

    // MARK: Mises a jour des jeux

    /// Regarde quels jeux Steam installes ont une version plus recente publiee.
    /// Silencieux en cas d'echec (hors ligne, Cidre trop ancien) : on ne sait pas, c'est tout.
    func checkUpdates(refresh: Bool = false) async {
        guard let found = try? await cli?.updates(refresh: refresh) else { return }
        updates = Dictionary(uniqueKeysWithValues: found.filter { !$0.upToDate }.map { ($0.appid, $0) })
    }

    /// Un jeu du client Steam se met a jour dans Steam : on ouvre ses telechargements.
    func openSteamDownloads() {
        if let url = URL(string: "steam://open/downloads") { NSWorkspace.shared.open(url) }
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

    /// Relance `cidre setup` sur le runtime en place (prefixe, pont Steam, SteamCMD).
    func reconfigureRuntime() {
        guard let cli, runtimeTask == nil else { return }
        runtimeStep = .configuring(L10n.string("Préparation"))
        runtimeTask = Task {
            do {
                try await RuntimeInstaller.configure(cli) { step in
                    Task { @MainActor in
                        if self.runtimeStep != nil { self.runtimeStep = step }
                    }
                }
            } catch is CancellationError {
                // arrete par l'utilisateur
            } catch {
                lastError = error.localizedDescription
            }
            runtimeStep = nil
            runtimeTask = nil
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
                loginNeeded = true
            } catch {
                lastError = error.localizedDescription
            }
            downloads[appid] = nil
            downloadTasks[appid] = nil
            await reload()
            await checkUpdates()
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
