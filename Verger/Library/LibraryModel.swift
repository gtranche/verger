import CidreBridge
import Foundation
import Observation

/// L'etat de la bibliotheque : la liste que rend `cidre list --json`, et les
/// jeux en cours de lancement.
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

    private(set) var state: State = .loading
    private(set) var games: [Game] = []
    /// Jeux dont `cidre play` n'a pas encore rendu la main.
    private(set) var running: Set<Int> = []
    var lastError: String?
    var filter: Filter = .all
    var search = ""

    /// Chemin de la CLI choisi a la main (sinon detection automatique).
    var cidrePath: String? = UserDefaults.standard.string(forKey: "cidrePath") {
        didSet { UserDefaults.standard.set(cidrePath, forKey: "cidrePath") }
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

    func reload() async {
        guard let cli = CidreCLI.locate(userChoice: cidrePath) else {
            self.cli = nil
            state = .cidreMissing
            return
        }
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
        try await cli?.info(appid: game.appid)
    }

    func play(_ game: Game) {
        guard let cli, !running.contains(game.appid) else { return }
        running.insert(game.appid)
        let log = Self.logsDirectory.appendingPathComponent("play-\(game.appid).log")
        Task {
            do {
                try await cli.play(appid: game.appid, log: log)
            } catch {
                lastError = error.localizedDescription
            }
            running.remove(game.appid)
            // Le jeu a tourne : sa date de dernier lancement a pu changer.
            await reload()
        }
    }

    static let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Verger")
}
