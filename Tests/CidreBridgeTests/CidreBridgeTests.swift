import Foundation
import Testing

@testable import CidreBridge

// Sorties reelles de la CLI (cidre list --json / cidre info --json).
private let listJSON = """
    [
      {"appid":464920,"nom":"Surviving Mars","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"wrapper":false,"chemin":"/Users/x/Library/Application Support/Steam/steamapps/common/Surviving Mars","taille":7219167160,"dernier_lancement":1790716411},
      {"appid":552500,"nom":"Warhammer: Vermintide 2","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"wrapper":true,"chemin":"/Users/x/Library/Application Support/Steam/steamapps/common/Warhammer Vermintide 2","taille":68863410968,"dernier_lancement":1791039401},
      {"id":"588650","appid":588650,"nom":"Dead Cells","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/Users/x/Library/Application Support/Cidre/games/588650","taille":2145895956,"dernier_lancement":0},
      {"id":"local-mon-jeu","appid":null,"nom":"Mon \\"Jeu\\"","plateforme":"windows","lancement":"cidre","source":"local","installe":true,"wrapper":null,"chemin":"/jeux/mon jeu","taille":0,"dernier_lancement":0}
    ]
    """

private let infoJSON = """
    {"appid":552500,"nom":"Warhammer: Vermintide 2","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"wrapper":true,"chemin":"/jeux/vt2","taille":68863410968,"dernier_lancement":1791039401,"sauvegardes":true,"options":{"tso":true,"vsync":true,"hud":false,"async":true,"fils_compilation":6,"eac_untrusted":true,"luajit":true},"options_perso":{"fils_compilation":6,"hud":false,"plus_tard":"x"}}
    """

@Test func decodeLaListe() throws {
    let games = try JSONDecoder().decode([Game].self, from: Data(listJSON.utf8))
    #expect(games.map(\.appid) == [464920, 552500, 588650, nil])
    // sans `id` (CLI d'avant les jeux hors Steam), l'appid en tient lieu
    #expect(games.map(\.id) == ["464920", "552500", "588650", "local-mon-jeu"])

    let mars = games[0]
    #expect(mars.platform == .macos)
    #expect(mars.launch == .native)
    #expect(mars.lastPlayed == Date(timeIntervalSince1970: 1_790_716_411))
    #expect(!mars.wrapperMissing)

    let vt2 = games[1]
    #expect(vt2.name == "Warhammer: Vermintide 2")
    #expect(vt2.sizeBytes == 68_863_410_968)
    #expect(vt2.wrapper == true)

    let deadCells = games[2]
    #expect(deadCells.source == .cidre)
    #expect(deadCells.wrapper == nil)
    #expect(deadCells.lastPlayed == nil)

    let local = games[3]
    #expect(local.source == .local)
    #expect(local.name == "Mon \"Jeu\"")
    #expect(!local.wrapperMissing)
}

@Test func decodeLesJeuxDuCompte() throws {
    let json = """
        [{"appid":242820,"nom":"140","plateformes":["windows","macos"],"installe":false},
         {"appid":552500,"nom":"Warhammer: Vermintide 2","plateformes":["windows"],"installe":true}]
        """
    let owned = try JSONDecoder().decode([OwnedGame].self, from: Data(json.utf8))
    #expect(owned[0].hasMac && owned[0].hasWindows && !owned[0].installed)
    #expect(!owned[1].hasMac && owned[1].installed)
}

@Test func litLAvancementDeSteamCMD() {
    let sortie = """
         Update state (0x61) downloading, progress: 1.22 (1048576 / 85850313)\r
         Update state (0x61) downloading, progress: 37.93 (32564012 / 85850313)\r
        """
    let progress = DownloadProgress.last(in: sortie)
    #expect(progress?.doneBytes == 32_564_012)
    #expect(progress?.totalBytes == 85_850_313)
    #expect(abs((progress?.fraction ?? 0) - 0.3793) < 0.0001)
    // la ligne de fin de SteamCMD (0 / 0) n'est pas un avancement
    #expect(DownloadProgress.last(in: " Update state (0x0) unknown, progress: 0.00 (0 / 0)") == nil)
    #expect(DownloadProgress.last(in: "Logging in user...OK") == nil)
}

@Test func wrapperAbsentSurUnJeuWindowsSteam() throws {
    let json = """
        {"appid":1,"nom":"X","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"wrapper":false,"chemin":"/x","taille":0,"dernier_lancement":0}
        """
    let game = try JSONDecoder().decode(Game.self, from: Data(json.utf8))
    #expect(game.wrapperMissing)
}

@Test func valeurInconnueNeFaitPasTomberLaListe() throws {
    let json = """
        [{"appid":1,"nom":"X","plateforme":"linux","lancement":"proton","source":"gog","installe":false,"wrapper":null,"chemin":"/x","taille":0,"dernier_lancement":0}]
        """
    let games = try JSONDecoder().decode([Game].self, from: Data(json.utf8))
    #expect(games[0].platform == .unknown)
}

@Test func decodeLaFiche() throws {
    let info = try JSONDecoder().decode(GameInfo.self, from: Data(infoJSON.utf8))
    #expect(info.game.appid == 552500)
    #expect(info.game.id == "552500")
    #expect(info.savesSynced)
    #expect(info.options.asyncShaders)
    #expect(info.options.compilerThreads == 6)
    // ce que le joueur a regle lui-meme ; une cle inconnue de Verger est ignoree
    #expect(info.overridden == [.compilerThreads, .hud])
    #expect(info.options.eacUntrusted)
    #expect(info.options.luajit)
    #expect(info.options.tso)
    // un Cidre qui ne connait pas ces options ne les fait pas apparaitre
    #expect(info.options.fullscreen == nil && info.options.gameMode == nil && info.options.overlay == nil)
}

@Test func optionsAbsentesPrennentLesDefauts() throws {
    let options = try JSONDecoder().decode(LaunchOptions.self, from: Data("{\"hud\":true}".utf8))
    var expected = LaunchOptions()
    expected.hud = true
    #expect(options == expected)
}

@Test func ordreDeRechercheDeLaCLI() {
    let urls = CidreCLI.candidates(
        userChoice: "/choisi/cidre",
        environment: ["VERGER_CIDRE": "/env/cidre", "PATH": "/a:/b"],
        home: URL(fileURLWithPath: "/Users/x"))
    #expect(urls.map(\.path) == [
        "/choisi/cidre",
        "/env/cidre",
        "/Users/x/Library/Application Support/Cidre/cidre/cidre",
        "/a/cidre",
        "/b/cidre",
    ])
}

/// Bout en bout sur une fausse CLI : execution, capture, decodage, erreurs.
@Test func executeUneFausseCLI() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("cidre")
    try """
        #!/bin/sh
        case "$1" in
          list) cat <<'JSON'
        \(listJSON)
        JSON
          ;;
          info) echo "jeu inconnu : $2" >&2; exit 1 ;;
          play) echo "lancement $2"; exit 0 ;;
          library) echo "Session SteamCMD non memorisee" >&2; exit 3 ;;
          add) printf '{"id":"local-x","appid":null,"nom":"%s","plateforme":"windows","lancement":"cidre","source":"local","installe":true,"wrapper":null,"chemin":"/x","taille":0,"dernier_lancement":0}\\n' "${3:-sans nom}" ;;
          prefix) echo "/prefixe/drive_c" ;;
          doctor) if [ -f "$(dirname "$0")/ANCIEN" ]; then echo "cidre — launcher Cidre"; else printf '\\n== Machine ==\\n  macOS : 27.0\\n== Wine repond-il ? ==\\n  -> PAS DE REPONSE apres 15 s\\n'; fi ;;
          stop) echo "stop ${2:-tout}" >> "$(dirname "$0")/reglages.txt"
                if [ "$2" = natif ]; then echo "jeu natif : quitte-le depuis Steam" >&2; exit 1; fi ;;
          saves) case "$2" in
                   set) [ -d "$4" ] || { echo "dossier introuvable : $4" >&2; exit 1; }
                        echo '{"id":"'"$3"'","configure":true,"etat":"jamais_sauvegarde","dossier":"'"$4"'","copie":"/c/'"$3"'","icloud":false,"local":{"fichiers":2,"octets":10,"modifie":1791000000},"sauvegarde":{"fichiers":0,"octets":0,"modifie":0},"a_sauvegarder":2,"a_restaurer":0,"historique":0}' ;;
                   unset|inconnu) echo '{"id":"'"${3:-$2}"'","configure":false}' ;;
                   *) echo '{"id":"'"$2"'","configure":true,"etat":"a_restaurer","dossier":"/jeu/save","copie":"/icloud/CidreSaves/'"$2"'","icloud":true,"local":{"fichiers":5,"octets":72154,"modifie":1791100000},"sauvegarde":{"fichiers":5,"octets":72200,"modifie":1791103600},"a_sauvegarder":0,"a_restaurer":1,"historique":3}' ;;
                 esac ;;
          sync) echo "sync $2 $3" >> "$(dirname "$0")/reglages.txt" ;;
          running) echo '["552500","local-x"]' ;;
          options) echo '{"options":{"tso":true,"vsync":false,"hud":true,"async":false,"fils_compilation":0,"eac_untrusted":false,"luajit":false,"plein_ecran":true,"gamemode":false,"overlay":true},"options_perso":{"vsync":false,"hud":true}}' ;;
          session) echo '{"compte":"joueur","connecte":false}' ;;
          logout) echo "logout" >> "$(dirname "$0")/reglages.txt" ;;
          updates) echo '[{"appid":588650,"build_installe":1,"build_disponible":23762174,"a_jour":false},{"appid":552500,"build_installe":7,"build_disponible":7,"a_jour":true}]' ;;
          set|unset) echo "$*" >> "$(dirname "$0")/reglages.txt"
                     if [ "$2" = inconnu ]; then echo "jeu inconnu : $2" >&2; exit 1; fi ;;
          rm) [ "$2" = local-x ] || { echo "jeu inconnu : $2" >&2; exit 1; } ;;
          dl) case "$2" in
                1) printf ' Update state (0x61) downloading, progress: 50.00 (5 / 10)\\n'; sleep 0.2
                   printf ' Update state (0x61) downloading, progress: 100.00 (10 / 10)\\nSuccess!\\n' ;;
                2) printf 'Logging in user...\\npassword: '; sleep 30 ;;
                3) echo "Echec SteamCMD (rc=8)."; exit 8 ;;
                5) echo "Session Steam non memorisee" >&2; exit 3 ;;
                4) sleep 30 ;;
              esac ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)

    let cli = try #require(CidreCLI.locate(userChoice: script.path, environment: [:], home: dir))
    #expect(try await cli.list().count == 4)

    await #expect(throws: CidreError.self) { try await cli.info(id: "42") }

    let log = dir.appendingPathComponent("logs/play.log")
    try await cli.play(id: "7", log: log)
    #expect(try String(contentsOf: log, encoding: .utf8) == "lancement 7\n")

    // sans session SteamCMD (code 3), l'erreur dit quoi faire
    await #expect(throws: CidreError.steamSessionMissing) { try await cli.library() }

    // hors Steam
    let game = try await cli.add(executable: URL(fileURLWithPath: "/jeux/x.exe"), name: "Mon jeu")
    #expect(game.id == "local-x" && game.name == "Mon jeu" && game.appid == nil)
    #expect(try await cli.prefix().path == "/prefixe/drive_c")
    try await cli.remove(id: "local-x")
    await #expect(throws: CidreError.self) { try await cli.remove(id: "local-y") }

    // options de lancement : les commandes exactes que recoit la CLI
    try await cli.setOption(id: "552500", .tso, to: false)
    try await cli.setOption(id: "local-x", .compilerThreads, to: 4)
    try await cli.resetOptions(id: "552500", .asyncShaders)
    try await cli.resetOptions(id: "552500")
    #expect(try String(contentsOf: dir.appendingPathComponent("reglages.txt"), encoding: .utf8) == """
        set 552500 tso false
        set local-x fils_compilation 4
        unset 552500 async
        unset 552500

        """)
    await #expect(throws: CidreError.self) { try await cli.setOption(id: "inconnu", .hud, to: true) }

    // reglages generaux : memes commandes, sur l'identifiant `defaut`
    let defaults = try await cli.defaultOptions()
    #expect(defaults.overridden == [.vsync, .hud])
    #expect(defaults.options.fullscreen == true && defaults.options.gameMode == false)
    #expect(defaults.options.overlay == true)
    try await cli.setOption(id: CidreCLI.defaultsID, .fullscreen, to: false)
    try await cli.resetOptions(id: CidreCLI.defaultsID, .vsync)

    // sauvegardes
    let saves = try await cli.saves(id: "588650")
    #expect(saves.configured && saves.state == .needsRestore && saves.onICloud)
    #expect(saves.folder == "/jeu/save" && saves.history == 3)
    #expect(saves.local?.bytes == 72154)
    #expect(saves.backup?.modified == Date(timeIntervalSince1970: 1_791_103_600))
    // un jeu dont Cidre ne connait pas le dossier : rien d'autre que « non configure »
    let unknown = try await cli.saves(id: "inconnu")
    #expect(!unknown.configured && unknown.state == .unknown && unknown.local == nil)
    try await cli.sync(id: "588650", .restore)
    try await cli.sync(id: "588650", .backup)
    #expect(try String(contentsOf: dir.appendingPathComponent("reglages.txt"), encoding: .utf8)
        .hasSuffix("sync 588650 restore\nsync 588650 backup\n"))
    let chosen = try await cli.setSavesFolder(id: "local-x", dir)
    #expect(chosen.state == .neverBackedUp && chosen.folder == dir.path && !chosen.onICloud)
    #expect(chosen.backup?.modified == nil)
    await #expect(throws: CidreError.self) { try await cli.setSavesFolder(id: "local-x", dir.appendingPathComponent("absent")) }
    #expect(try await !cli.resetSavesFolder(id: "local-x").configured)

    // diagnostic : le texte de Cidre ; un Cidre d'avant n'en a pas
    let diagnostic = try await cli.doctor()
    #expect(diagnostic.contains("== Wine repond-il ? ==") && diagnostic.contains("PAS DE REPONSE"))
    try "".write(to: dir.appendingPathComponent("ANCIEN"), atomically: true, encoding: .utf8)
    await #expect(throws: CidreError.self) { _ = try await cli.doctor() }

    // forcer l'arret : un jeu, ou tout ; un jeu natif est refuse par Cidre
    try await cli.stop(id: "588650")
    try await cli.stop()
    #expect(try String(contentsOf: dir.appendingPathComponent("reglages.txt"), encoding: .utf8)
        .hasSuffix("stop 588650\nstop tout\n"))
    await #expect(throws: CidreError.self) { try await cli.stop(id: "natif") }

    // jeux en cours
    #expect(try await cli.running() == ["552500", "local-x"])

    // session Steam
    #expect(try await cli.session() == SteamSession(account: "joueur", connected: false))
    try await cli.logout()
    let journal = try String(contentsOf: dir.appendingPathComponent("reglages.txt"), encoding: .utf8)
    #expect(journal.contains("set defaut plein_ecran false\nunset defaut vsync\n"))
    #expect(journal.hasSuffix("logout\n"))

    // telechargement : avancement, session absente, echec, annulation
    let seen = Seen()
    try await cli.download(appid: 1) { seen.add($0) }
    #expect(seen.all.last == DownloadProgress(fraction: 1, doneBytes: 10, totalBytes: 10))
    #expect(seen.all.contains(DownloadProgress(fraction: 0.5, doneBytes: 5, totalBytes: 10)))

    await #expect(throws: CidreError.steamSessionMissing) { try await cli.download(appid: 2) { _ in } }
    // Cidre s'arrete de lui-meme sans session : code 3
    await #expect(throws: CidreError.steamSessionMissing) { try await cli.download(appid: 5) { _ in } }

    // mises a jour des jeux
    let updates = try await cli.updates()
    #expect(updates.map(\.upToDate) == [false, true])
    #expect(updates[0].appid == 588650 && updates[0].availableBuild == 23_762_174)

    do {
        try await cli.download(appid: 3) { _ in }
        Issue.record("un dl en echec doit lever")
    } catch let CidreError.commandFailed(_, status, message) {
        #expect(status == 8)
        #expect(message.contains("Echec SteamCMD"))
    }

    let started = Date()
    let task = Task { try await cli.download(appid: 4) { _ in } }
    try await Task.sleep(for: .milliseconds(500))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(Date().timeIntervalSince(started) < 10)
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DownloadProgress] = []
    func add(_ value: DownloadProgress) { lock.lock(); values.append(value); lock.unlock() }
    var all: [DownloadProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

/// Le vrai `cidre doctor`, a la demande (il demarre Wine, une dizaine de secondes) :
///   VERGER_ESSAI_DIAGNOSTIC=/chemin/vers/cidre Scripts/test.sh --filter leVraiDiagnostic
@Test(.enabled(if: ProcessInfo.processInfo.environment["VERGER_ESSAI_DIAGNOSTIC"] != nil))
func leVraiDiagnostic() async throws {
    let cli = CidreCLI(executable: URL(fileURLWithPath: ProcessInfo.processInfo.environment["VERGER_ESSAI_DIAGNOSTIC"]!))
    let text = try await cli.doctor()
    print(text)
    #expect(text.contains("== Machine ==") && text.contains("== Fin du diagnostic =="))
}
