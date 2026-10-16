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
    /// Un lancement que Cidre a arrete pour proteger le nuage Steam (code 7) :
    /// le jeu, et les sauvegardes qui manquent sur ce Mac.
    var cloudGuard: CloudGuardRequest?
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
    /// Quand `updates` a ete demande a Cidre pour la derniere fois.
    private var lastUpdatesCheck = Date.distantPast
    /// Ce qu'a donne la derniere mise a jour d'avant lancement quand elle n'a
    /// pas ete faite (hors ligne, session absente, place...), par appid : le
    /// jeu est parti dans sa version installee, la fiche dit pourquoi.
    private(set) var updateNotices: [Int: String] = [:]
    /// Ce que Cidre a annonce au lancement sur les shaders du jeu (premier
    /// lancement, cache a refaire), par id de jeu : dit tant que le jeu tourne.
    private(set) var shaderNotices: [String: String] = [:]
    /// Les jeux que « Jouer » est en train de mettre a jour avant de les lancer.
    private var updatingBeforeLaunch: Set<Int> = []
    private var playTasks: [String: Task<Void, Never>] = [:]
    /// Ce Cidre met-il a jour avant de lancer (`cidre play --json`, option
    /// `maj_avant_lancement`) ? `nil` : pas encore demande.
    private var updatesBeforeLaunch: Bool?
    /// Telechargements en cours, par appid.
    private(set) var downloads: [Int: DownloadProgress] = [:]
    /// Les reprises de bouteille en cours (quelques secondes).
    private(set) var importing: Set<Int> = []
    /// Ce qu'il est advenu des sauvegardes du dernier jeu repris, en une ligne.
    private(set) var importNotice: String?
    private var downloadTasks: [Int: Task<Void, Never>] = [:]

    /// Ou vivent les jeux Cidre (`cidre emplacements`) : ce Mac, des disques
    /// externes. Vide tant qu'on ne l'a pas demande.
    private(set) var locations: [StorageLocation] = []
    /// Des emplacements Cidre trouves sur un disque branche, pas encore ajoutes.
    private(set) var detectedLocations: [DetectedLocation] = []
    /// Ce Cidre connait-il les emplacements ? `nil` : pas encore demande.
    private(set) var locationsSupported: Bool?
    /// Les deplacements que Verger a lances et qui tournent, par id de jeu.
    private(set) var moves: [String: MoveStatus] = [:]
    private var moveTasks: [String: Task<Void, Never>] = [:]
    /// L'emplacement choisi dans « Installer un jeu Steam » ; `nil` : celui par defaut.
    var installLocation: String?

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

    /// Quand la bibliotheque a ete relue pour la derniere fois.
    private var lastReload = Date.distantPast

    /// Relit la bibliotheque si elle a pu changer sans Verger : un jeu
    /// installe depuis un terminal, par une autre session, ou pendant que
    /// l'application dormait en arriere-plan. Appelee quand Verger revient au
    /// premier plan ; sans effet si la derniere lecture est toute recente.
    func reloadIfStale() async {
        guard Date().timeIntervalSince(lastReload) > 15 else { return }
        await reload()
        if locationsSupported != false { await loadLocations() }
        // « pas a jour » aussi a pu changer sans Verger (un `cidre dl` au
        // Terminal, un build publie depuis) : on ne garde pas un vieux verdict.
        if Date().timeIntervalSince(lastUpdatesCheck) > Self.updatesMaxAge { await checkUpdates() }
    }

    /// Au-dela, l'etat des mises a jour est redemande a Cidre quand Verger
    /// revient au premier plan (Cidre, lui, garde la reponse de Steam 30 minutes).
    static let updatesMaxAge: TimeInterval = 10 * 60

    func reload() async {
        lastReload = Date()
        guard var cli = CidreCLI.locate(userChoice: cidrePath) else {
            self.cli = nil
            state = .cidreMissing
            return
        }
        cli.steamUser = steamUser
        // un autre Cidre (choisi, installe, mis a jour) : ce qu'il sait faire est a redemander
        if self.cli?.executable != cli.executable { updatesBeforeLaunch = nil }
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

    // MARK: Arreter un jeu, lire son journal

    /// Force l'arret d'un jeu lance par Cidre (ou, sans jeu, de tout ce que
    /// Cidre fait tourner). Ce qui n'etait pas sauvegarde dans la partie est perdu.
    func stop(_ game: Game? = nil) async {
        guard let cli else { return }
        do {
            try await cli.stop(id: game?.id)
        } catch {
            lastError = error.localizedDescription
        }
        if let game { launched.remove(game.id) }
        await refreshRunning()
        await checkRuntime()
    }

    /// Ce qu'un lancement a laisse comme traces, nettoye de ce qui identifie
    /// l'utilisateur : la sortie de la commande de lancement, puis la fin du
    /// journal du jeu (son dernier lancement, sans les lignes de trace).
    struct LaunchLog: Equatable {
        var command: [String] = []
        var journal: [String] = []
        var isEmpty: Bool { command.isEmpty && journal.isEmpty }
    }

    func launchLog(of game: Game, lines: Int = 1500) async -> LaunchLog {
        let anonymizer = Anonymizer.current(steamAccount: steamSession?.account ?? runtimeStatus?.steamAccount ?? steamUser)
        var log = LaunchLog()
        let playLog = Self.logsDirectory.appendingPathComponent("play-\(game.id).log")
        if let text = try? String(contentsOf: playLog, encoding: .utf8) {
            log.command = text.split(whereSeparator: \.isNewline).suffix(60).map { anonymizer.clean(String($0)) }
        }
        if let cli {
            log.journal = ((try? await cli.log(id: game.id, lines: lines)) ?? []).map(anonymizer.clean)
        }
        return log
    }

    /// Le diagnostic de l'installation (`cidre doctor`), precede de ce que
    /// Verger sait de lui-meme, et nettoye de ce qui identifie l'utilisateur.
    func diagnostic() async -> String {
        let anonymizer = Anonymizer.current(steamAccount: steamSession?.account ?? runtimeStatus?.steamAccount ?? steamUser)
        let verger = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        var text = "== Verger ==\n  version     : \(verger)\n  \(SystemInfo.current.summary)\n"
        guard let cli else {
            return text + "\n" + L10n.string("Cidre n'est pas installé : il n'y a rien à diagnostiquer.")
        }
        do {
            text += try await cli.doctor()
        } catch {
            text += "\n" + L10n.string("Ce Cidre ne sait pas se diagnostiquer. Mets-le à jour, puis relance le diagnostic.")
                + "\n" + error.localizedDescription
        }
        return anonymizer.clean(text)
    }

    /// Le journal detaille d'un jeu : Wine y ecrit ses messages d'erreur au
    /// prochain lancement. `nil` si ce Cidre ne connait pas l'option.
    func detailedLog(of game: Game) async -> Bool? {
        await cli?.boolOption(id: game.id, named: "journal_detaille")
    }

    func setDetailedLog(of game: Game, _ on: Bool) async {
        do {
            try await cli?.setOption(id: game.id, named: "journal_detaille", to: on)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Signaler un probleme

    /// Un incident pret a partir, et le journal complet a y joindre.
    struct PreparedReport {
        let report: IssueReport
        /// La fin du journal du jeu (plus longue que dans l'incident), deja nettoyee.
        let attachment: URL?
    }

    /// Prepare un incident GitHub : pour un jeu (il va chez Cidre, avec la fin de
    /// son journal) ou pour l'application (chez Verger). Tout ce qui identifie
    /// l'utilisateur en est retire.
    func prepareReport(game: Game?, error: String?) async -> PreparedReport {
        // l'etat du moment, pas celui lu a l'ouverture de Verger : « un jeu
        // tourne-t-il ? » est justement ce qu'un rapport doit dire juste
        if let fresh = try? await cli?.status() { runtimeStatus = fresh }
        let anonymizer = Anonymizer.current(steamAccount: steamSession?.account ?? runtimeStatus?.steamAccount ?? steamUser)
        let verger = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let cidre = runtimeStatus.map { $0.isDevelopmentCheckout ? "dev" : $0.version } ?? "?"

        let happened = L10n.string("Ce qui s'est passé")
        let toFill = L10n.string("(À compléter : ce que tu faisais, ce que tu attendais, ce que tu as vu.)")
        let errorTitle = L10n.string("Message d'erreur")
        let environment = L10n.string("Environnement")
        let gameTitle = L10n.string("Jeu")
        let fence = "```"
        var text = "**\(happened)**\n\n\(toFill)\n"
        if let error, !error.isEmpty {
            text += "\n**\(errorTitle)**\n\(fence)text\n\(anonymizer.clean(error))\n\(fence)\n"
        }
        text += "\n**\(environment)**\n- Verger \(verger) · Cidre \(cidre)\n- \(SystemInfo.current.summary)\n"
        if let s = runtimeStatus {
            // l'etat de l'installation, tel que Cidre le nomme
            let client = s.steamClientInstalled.map { "\($0)" } ?? "?"
            text += "- runtime=\(s.runtimePresent) prefixe=\(s.prefixReady) steamcmd=\(s.steamcmdPresent) client_steam=\(client) jeu_en_cours=\(s.gameRunning)\n"
        }

        var log: [String] = []
        var attachment: URL?
        if let game {
            let options = (try? await cli?.info(id: game.id))?.options
            text += "\n**\(gameTitle)**\n- \(game.name) (\(game.id)) — \(game.platform.rawValue), \(game.source.rawValue)\n"
            if let options, game.launch == .cidre { text += "- \(options.summary)\n" }
            if let cli {
                log = ((try? await cli.log(id: game.id, lines: 250)) ?? []).map(anonymizer.clean)
                // la piece jointe : une fin de journal plus longue que l'adresse n'en porte
                let long = ((try? await cli.log(id: game.id, lines: 4000)) ?? []).map(anonymizer.clean)
                if long.count > log.count || log.count > 40 {
                    let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                        .replacingOccurrences(of: ":", with: "")
                    let file = Self.logsDirectory.appendingPathComponent("rapports/journal-\(game.id)-\(stamp).txt")
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if (try? long.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)) != nil {
                        attachment = file
                    }
                }
            }
        }
        let headline = error.flatMap { anonymizer.clean($0).split(whereSeparator: \.isNewline).first.map { String($0.prefix(90)) } }
        let title = [game?.name, headline].compactMap { $0 }.joined(separator: " : ")
        let report = IssueReport(
            repository: game == nil ? "gtranche/verger" : "gtranche/cidre",
            title: game != nil && headline == nil ? "\(title) : " : title,
            text: text, logTitle: L10n.string("Fin du journal"), log: log)
        return PreparedReport(report: report, attachment: attachment)
    }

    // MARK: Partager mon resultat

    /// Ce qu'un rapport de jeu dit de la machine et de l'installation : la puce
    /// et la memoire, la version de Cidre, le profil effectif du jeu et le
    /// diagnostic anonymise. Chaque morceau que ce Cidre ne sait pas donner
    /// reste `nil` ; le rapport part sans lui.
    func gameReportContext(for game: Game) async -> GameReport.Context {
        var context = GameReport.Context(machine: SystemInfo.current.machineLabel, gpuFamily: MetalFamily.current)
        if let fresh = try? await cli?.status() { runtimeStatus = fresh }
        context.cidreVersion = runtimeStatus?.version
        context.options = (try? await cli?.info(id: game.id))?.options
        if cli != nil {
            // le diagnostic, deja nettoye de ce qui identifie l'utilisateur
            context.diagnostic = await diagnostic()
        }
        return context
    }

    /// Le texte complet d'un rapport, ecrit dans un fichier : une adresse web ne
    /// porte que quelques kilo-octets, et l'utilisateur peut glisser ce fichier
    /// dans l'incident.
    func saveGameReport(_ report: IssueReport, gameID: String) -> URL? {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let file = Self.logsDirectory.appendingPathComponent("rapports/rapport-\(gameID)-\(stamp).md")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? report.body().write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        return file
    }

    /// Le jeu dont une partie vient de finir, et pour lequel Verger propose,
    /// une fois, de partager le resultat. `nil` : rien a proposer.
    var shareSuggestion: Game?
    /// Les jeux pour lesquels la proposition a deja ete faite : on ne la refait pas.
    private var shareSuggested: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "partageProposes") ?? []) {
        didSet { UserDefaults.standard.set(Array(shareSuggested).sorted(), forKey: "partageProposes") }
    }
    /// Une partie plus courte que ca ne dit rien du jeu.
    static let shareSuggestionMinimumPlay: TimeInterval = 10 * 60

    /// Un jeu vient de s'arreter apres une vraie partie : on proposera de
    /// partager le resultat, discretement, et une seule fois par jeu.
    private func noteEndedGames(before: Set<String>, startedAt: [String: Date], now: Date) {
        // la partie est finie : ce qui devait etre compile l'a ete (ou le sera la prochaine fois)
        for id in before.subtracting(running) { shaderNotices[id] = nil }
        for id in before.subtracting(running) {
            guard let since = startedAt[id], now.timeIntervalSince(since) >= Self.shareSuggestionMinimumPlay,
                  !shareSuggested.contains(id),
                  let game = games.first(where: { $0.id == id }), game.launch == .cidre else { continue }
            shareSuggested.insert(id)
            shareSuggestion = game
        }
    }

    func dismissShareSuggestion() {
        shareSuggestion = nil
    }

    // MARK: Sauvegardes

    /// Ou en est la synchro des sauvegardes d'un jeu ; `nil` si Cidre est trop
    /// ancien pour le dire.
    func saveStatus(of game: Game) async -> SaveStatus? {
        try? await cli?.saves(id: game.id)
    }

    /// Sauvegarde vers iCloud, ou reprend ce qui y est plus recent, puis rend
    /// l'etat a jour.
    func syncSaves(of game: Game, _ direction: CidreCLI.SyncDirection) async -> SaveStatus? {
        guard let cli else { return nil }
        do {
            try await cli.sync(id: game.id, direction)
        } catch {
            lastError = error.localizedDescription
        }
        return try? await cli.saves(id: game.id)
    }

    /// Dit a Cidre ou ce jeu range ses sauvegardes.
    func setSavesFolder(of game: Game, _ folder: URL) async -> SaveStatus? {
        guard let cli else { return nil }
        do {
            return try await cli.setSavesFolder(id: game.id, folder)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
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

    /// Ce que fait « Jouer » pour ce jeu : le lancer, ou le mettre a jour d'abord.
    func playPlan(for game: Game) -> PlayPlan {
        PlayPlan.plan(for: game, update: game.appid.flatMap { updates[$0] })
    }

    /// Lance le jeu. Un jeu du dossier Cidre dont Steam publie un build plus
    /// recent est d'abord mis a jour (avancement dans `downloads`), puis lance ;
    /// si la mise a jour est impossible, il part dans sa version installee et
    /// `updateNotices` dit pourquoi. `skipUpdate` : jouer tout de suite.
    func play(_ game: Game, skipUpdate: Bool = false, acceptCloudLoss: Bool = false) {
        guard let cli, !running.contains(game.id) else { return }
        // son disque est debranche, ou il est en plein deplacement : Cidre refuserait
        if !game.online {
            lastError = offlineMessage(for: game)
            return
        }
        if moves[game.id] != nil { return }
        // deja en train d'etre telecharge : on ne lance pas un jeu a moitie remplace
        if let appid = game.appid, downloads[appid] != nil { return }
        launched.insert(game.id)
        if let appid = game.appid { updateNotices[appid] = nil }
        shaderNotices[game.id] = nil
        let log = Self.logsDirectory.appendingPathComponent("play-\(game.id).log")
        playTasks[game.id] = Task {
            await refreshRunning()
            do {
                if await canUpdateBeforeLaunch(cli) {
                    // Cidre verifie, met a jour s'il le faut, puis lance : il le raconte.
                    try await cli.play(id: game.id, log: log, skipUpdate: skipUpdate, acceptCloudLoss: acceptCloudLoss) { event in
                        Task { @MainActor in self.handle(event, for: game) }
                    }
                } else {
                    // Un Cidre plus ancien lance sans regarder : Verger met a jour lui-meme.
                    if !skipUpdate, let appid = game.appid, playPlan(for: game) == .updateThenPlay {
                        updatingBeforeLaunch.insert(appid)
                        let outcome = await performDownload(appid: appid)
                        updatingBeforeLaunch.remove(appid)
                        if outcome == .cancelled { throw CancellationError() }
                        if outcome == .failed {
                            // l'erreur est montree par ailleurs ; le jeu installe reste jouable
                            updateNotices[appid] = L10n.string("La mise à jour a échoué : le jeu est lancé dans sa version installée.")
                        }
                    }
                    try await cli.play(id: game.id, log: log, acceptCloudLoss: acceptCloudLoss)
                }
            } catch is CancellationError {
                // la mise a jour a ete arretee : le jeu n'est pas lance
            } catch CidreError.updateRunning {
                lastError = CidreError.updateRunning.localizedDescription
            } catch let CidreError.cloudSavesAtRisk(files) {
                cloudGuard = CloudGuardRequest(game: game, files: files)
            } catch let CidreError.refused(message) {
                // disque debranche entre-temps, deplacement en cours : la phrase de Cidre
                lastError = message
            } catch {
                lastError = LaunchFailureExplainer.explain(log: log, fallback: error.localizedDescription)
            }
            if let appid = game.appid, updatingBeforeLaunch.remove(appid) != nil { downloads[appid] = nil }
            playTasks[game.id] = nil
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
            // Le jeu a tourne : sa date de dernier lancement a pu changer, et
            // son build si Cidre l'a mis a jour.
            await reload()
            if game.source == .cidre { await checkUpdates() }
        }
    }

    /// Ce Cidre sait-il mettre a jour avant de lancer ? Il le dit par l'option
    /// `maj_avant_lancement` de ses reglages generaux.
    private func canUpdateBeforeLaunch(_ cli: CidreCLI) async -> Bool {
        if let known = updatesBeforeLaunch { return known }
        // (un echec passager n'est pas retenu : on redemandera)
        guard let defaults = try? await cli.defaultOptions() else { return false }
        let known = defaults.options.updateBeforeLaunch != nil
        updatesBeforeLaunch = known
        return known
    }

    /// Un evenement de `cidre play --json` : ou en est la mise a jour d'avant
    /// lancement, et s'il faudra compiler les shaders du jeu.
    private func handle(_ event: PlayEvent, for game: Game) {
        // (un evenement arrive apres la fin de la commande ne doit rien ressusciter)
        guard playTasks[game.id] != nil else { return }
        if case let .shaders(status) = event {
            shaderNotices[game.id] = status.announcement
            return
        }
        guard let appid = game.appid else { return }
        switch event {
        case .refused:
            // (l'erreur arrive a la fin de la commande, avec la phrase de Cidre)
            break
        case .shaders:
            break
        case .launching:
            if updatingBeforeLaunch.remove(appid) != nil { downloads[appid] = nil }
        case let .update(status):
            switch status.state {
            case .running:
                updatingBeforeLaunch.insert(appid)
                downloads[appid] = status.progress ?? downloads[appid] ?? DownloadProgress()
            case .done, .upToDate:
                if updatingBeforeLaunch.remove(appid) != nil { downloads[appid] = nil }
                updates[appid] = nil
            case .failed, .unknown:
                if updatingBeforeLaunch.remove(appid) != nil { downloads[appid] = nil }
                // pas faite, ou pas verifiee : le jeu part quand meme, la fiche dit pourquoi
                if let explanation = status.explanation {
                    updateNotices[appid] = explanation + " " + L10n.string("Le jeu est lancé dans sa version installée.")
                }
            case .ignored, .available, .checking:
                // (laissee de cote : la fiche le dit deja, d'apres `updates`)
                break
            }
        }
    }

    // MARK: Jeux en cours, et Discord

    /// Demande a Cidre ce qui tourne, et met Discord a jour. Appelee toutes les
    /// quelques secondes tant que la fenetre est ouverte.
    func refreshRunning() async {
        let before = running
        let startedAt = runningSince
        // un Cidre d'avant `cidre running` : on ne sait que ce qu'on a lance
        if let ids = try? await cli?.running() { reported = Set(ids) }
        // un deplacement lance ailleurs (au Terminal) : son avancement, et sa fin
        if games.contains(where: { $0.move?.isRunning == true && moveTasks[$0.id] == nil }) { await reload() }
        let now = Date()
        for id in running where runningSince[id] == nil { runningSince[id] = now }
        runningSince = runningSince.filter { running.contains($0.key) }
        noteEndedGames(before: before, startedAt: startedAt, now: now)
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
        lastUpdatesCheck = Date()
        guard let found = try? await cli?.updates(refresh: refresh) else { return }
        updates = Dictionary(found.filter(\.needsUpdate).map { ($0.appid, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Demande a Cidre de rafraichir en fond ce qu'il sait des builds publies,
    /// pour que le premier lancement n'attende pas Steam. Rend la main tout de suite.
    func warmUpdates() async {
        await cli?.refreshUpdatesInBackground()
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
    /// Reprend un jeu trouve dans une bouteille CrossOver, Whisky ou Heroic.
    /// Rapide (clone sur le meme volume) : pas d'avancement, la bibliotheque se
    /// recharge a la fin.
    func importGame(appid: Int) {
        guard let cli, !importing.contains(appid) else { return }
        importing.insert(appid)
        let name = owned.first { $0.appid == appid }?.name ?? String(appid)
        let location = chosenInstallLocation
        Task {
            do {
                importNotice = try await cli.importGame(appid: appid, location: location).saves?.notice(game: name)
            } catch {
                lastError = error.localizedDescription
            }
            importing.remove(appid)
            await reload()
            await loadOwned(refresh: true)
        }
    }

    /// Telecharge un jeu : un nouveau jeu va dans l'emplacement choisi a
    /// l'installation (ou celui par defaut), un jeu installe est mis a jour la
    /// ou il est.
    func download(appid: Int) {
        guard cli != nil, downloadTasks[appid] == nil, downloads[appid] == nil else { return }
        downloads[appid] = DownloadProgress()
        let isNew = !games.contains { $0.appid == appid && $0.source == .cidre }
        let location = isNew ? chosenInstallLocation : nil
        downloadTasks[appid] = Task {
            _ = await performDownload(appid: appid, location: location)
            downloadTasks[appid] = nil
        }
        // le dossier du jeu apparait des le debut : on le montre dans la grille
        Task {
            try? await Task.sleep(for: .seconds(3))
            await reload()
        }
    }

    private enum DownloadOutcome {
        case done, cancelled, failed
    }

    /// `cidre dl`, attendu jusqu'au bout : l'avancement va dans `downloads`, et
    /// l'etat des mises a jour est relu a la fin.
    private func performDownload(appid: Int, location: String? = nil) async -> DownloadOutcome {
        guard let cli else { return .failed }
        downloads[appid] = downloads[appid] ?? DownloadProgress()
        var outcome = DownloadOutcome.done
        do {
            try await cli.download(appid: appid, location: location) { progress in
                Task { @MainActor in
                    // un avancement arrive apres la fin ne doit pas la ressusciter
                    if self.downloads[appid] != nil { self.downloads[appid] = progress }
                }
            }
            // le jeu vient d'etre mis a jour, quoi qu'en dise un cache en retard
            updates[appid] = nil
            updateNotices[appid] = nil
        } catch is CancellationError {
            // arrete par l'utilisateur : SteamCMD reprendra ou il en etait
            outcome = .cancelled
        } catch CidreError.steamSessionMissing {
            ownedState = .sessionMissing
            loginNeeded = true
            outcome = .failed
        } catch {
            lastError = error.localizedDescription
            outcome = .failed
        }
        downloads[appid] = nil
        await reload()
        await checkUpdates()
        if ownedState == .loaded { await loadOwned() }
        return outcome
    }

    func cancelDownload(appid: Int) {
        downloadTasks[appid]?.cancel()
        // une mise a jour d'avant lancement : on arrete tout, le jeu ne part pas
        // (jamais une fois le jeu lance : arreter la commande l'arreterait)
        if updatingBeforeLaunch.contains(appid) { playTasks[String(appid)]?.cancel() }
    }

    /// Version macOS : c'est le client Steam qui l'installe, dans sa propre
    /// bibliotheque. On lui ouvre sa fenetre d'installation.
    func installNative(appid: Int) {
        if let url = URL(string: "steam://install/\(appid)") { NSWorkspace.shared.open(url) }
    }

    // MARK: Emplacements

    /// Ou va un jeu qu'on installe : l'emplacement choisi s'il accepte encore
    /// des jeux, sinon celui par defaut, sinon ce Mac (le defaut est debranche).
    var effectiveInstallLocation: StorageLocation? {
        let usable = locations.filter(\.acceptsGames)
        if let id = installLocation, let chosen = usable.first(where: { $0.id == id }) { return chosen }
        return usable.first(where: \.isDefault) ?? usable.first(where: \.isMain) ?? usable.first
    }

    /// `--vers` pour `cidre dl` et `cidre import` ; `nil` : celui par defaut de
    /// Cidre (ou un Cidre sans emplacements).
    private var chosenInstallLocation: String? {
        guard locationsSupported == true, let location = effectiveInstallLocation else { return nil }
        return location.isDefault ? nil : location.id
    }

    func location(id: String?) -> StorageLocation? {
        guard let id else { return nil }
        return locations.first { $0.id == id }
    }

    /// Le nom de l'emplacement d'un jeu, pour le joueur (le volume d'un disque).
    func locationName(of game: Game) -> String? {
        location(id: game.location)?.name ?? game.location.flatMap { $0 == "principal" ? L10n.string("Ce Mac") : nil }
    }

    func offlineMessage(for game: Game) -> String {
        if let name = locationName(of: game) {
            return L10n.format("%@ est sur « %@ », qui n'est pas branché. Branche ce disque pour jouer : le jeu n'est ni désinstallé ni perdu.", game.name, name)
        }
        return L10n.format("%@ est sur un disque qui n'est pas branché. Branche ce disque pour jouer : le jeu n'est ni désinstallé ni perdu.", game.name)
    }

    /// Relit les emplacements. Silencieux en cas d'echec : on garde ce qu'on savait.
    func loadLocations() async {
        guard let cli else { return }
        do {
            if let found = try await cli.storageLocations() {
                locations = found.locations
                detectedLocations = found.detected
                locationsSupported = true
            } else {
                locations = []
                detectedLocations = []
                locationsSupported = false
            }
        } catch {
            // un echec passager : on redemandera
        }
    }

    /// Un disque a ete branche, debranche ou renomme : ses jeux passent en
    /// ligne ou hors ligne.
    func volumesChanged() async {
        await reload()
        if locationsSupported != false { await loadLocations() }
    }

    /// Ajoute un disque ou un dossier ; rend l'emplacement, ou `nil` (l'erreur
    /// est dans `lastError` : FAT32, lecture seule, dossier dans un autre...).
    @discardableResult
    func addLocation(_ folder: URL) async -> StorageLocation? {
        guard let cli else { return nil }
        var added: StorageLocation?
        do {
            added = try await cli.addStorageLocation(folder)
        } catch {
            lastError = error.localizedDescription
        }
        await loadLocations()
        // ses jeux, s'il en portait deja, entrent dans la bibliotheque
        await reload()
        return added
    }

    func removeLocation(_ location: StorageLocation) async {
        guard let cli else { return }
        do {
            try await cli.removeStorageLocation(id: location.id)
        } catch {
            lastError = error.localizedDescription
        }
        if installLocation == location.id { installLocation = nil }
        await loadLocations()
        await reload()
    }

    func setDefaultLocation(_ location: StorageLocation) async {
        guard let cli else { return }
        do {
            try await cli.setDefaultStorageLocation(id: location.id)
        } catch {
            lastError = error.localizedDescription
        }
        await loadLocations()
    }

    /// Le deplacement d'un jeu, d'ou qu'il ait ete lance : celui que Verger
    /// suit, sinon ce qu'en dit `cidre list` (en cours ailleurs, ou inacheve).
    func moveStatus(of game: Game) -> MoveStatus? {
        moves[game.id] ?? game.move
    }

    /// Deplace un jeu Cidre vers un autre emplacement. L'avancement est dans
    /// `moves` ; a la fin (ou en cas d'echec), la bibliotheque est relue.
    func move(_ game: Game, to location: StorageLocation) {
        guard let cli, moveTasks[game.id] == nil, !running.contains(game.id) else { return }
        moves[game.id] = MoveStatus(state: .running, phase: .preparation, from: game.location, to: location.id)
        moveTasks[game.id] = Task {
            do {
                try await cli.move(id: game.id, to: location.id) { event in
                    Task { @MainActor in
                        // un evenement arrive apres la fin ne doit rien ressusciter
                        guard self.moveTasks[game.id] != nil, event.state == .running else { return }
                        let previous = self.moves[game.id]
                        self.moves[game.id] = MoveStatus(
                            state: .running, phase: event.phase ?? previous?.phase,
                            from: previous?.from, to: previous?.to,
                            progress: event.progress ?? (event.phase == .copie ? previous?.progress : nil))
                    }
                }
            } catch is CancellationError {
                // arrete : l'original est intact, la fiche propose de reprendre
            } catch {
                lastError = error.localizedDescription
            }
            moves[game.id] = nil
            moveTasks[game.id] = nil
            await reload()
            await loadLocations()
        }
    }

    /// Arrete un deplacement en cours ; il pourra reprendre ou il en etait.
    func stopMove(_ game: Game) {
        if let task = moveTasks[game.id] {
            task.cancel()
            return
        }
        // lance ailleurs (au Terminal) : Cidre l'arrete
        guard let cli else { return }
        Task {
            do {
                try await cli.stopMove(id: game.id)
            } catch {
                lastError = error.localizedDescription
            }
            await reload()
        }
    }

    /// Reprend un deplacement inacheve, vers l'emplacement ou il allait.
    func resumeMove(_ game: Game) {
        guard let target = location(id: moveStatus(of: game)?.to) else {
            lastError = L10n.string("L'emplacement où allait ce jeu n'est plus connu : choisis-en un autre avec « Déplacer vers… ».")
            return
        }
        guard target.online else {
            lastError = L10n.format("« %@ » n'est pas branché : branche-le pour reprendre le déplacement.", target.name)
            return
        }
        move(game, to: target)
    }

    /// Abandonne un deplacement : la copie entamee est effacee, le jeu reste ou il etait.
    func abandonMove(_ game: Game) async {
        moveTasks[game.id]?.cancel()
        guard let cli else { return }
        do {
            try await cli.abandonMove(id: game.id)
        } catch {
            lastError = error.localizedDescription
        }
        await reload()
        await loadLocations()
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

/// Ce que Verger montre quand Cidre refuse un lancement pour proteger le nuage
/// Steam : quelles sauvegardes manquent, qu'elles restent dans le nuage, et ce
/// que « Lancer quand meme » ferait.
struct CloudGuardRequest {
    let game: Game
    let files: [String]

    var message: String {
        let list = files.isEmpty ? L10n.string("(voir le journal du lancement)") : files.map { "• " + $0 }.joined(separator: "\n")
        return L10n.format("Steam croit ces sauvegardes de %@ présentes sur ce Mac, mais elles n'y sont plus :\n%@\n\nElles sont toujours dans le nuage Steam. Si tu lances le jeu quand même, Steam les retirera du nuage quand tu le quitteras. Pour les garder, remets-les à leur place avant de jouer (elles se téléchargent depuis la page Steam Cloud de ton compte).", game.name, list)
    }
}
