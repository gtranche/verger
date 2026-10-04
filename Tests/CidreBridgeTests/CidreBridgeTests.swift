import Foundation
import Testing

@testable import CidreBridge

// Sorties reelles de la CLI (cidre list --json / cidre info --json).
private let listJSON = """
    [
      {"appid":464920,"nom":"Surviving Mars","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"wrapper":false,"chemin":"/Users/x/Library/Application Support/Steam/steamapps/common/Surviving Mars","taille":7219167160,"dernier_lancement":1790716411},
      {"appid":552500,"nom":"Warhammer: Vermintide 2","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"wrapper":true,"chemin":"/Users/x/Library/Application Support/Steam/steamapps/common/Warhammer Vermintide 2","taille":68863410968,"dernier_lancement":1791039401},
      {"appid":588650,"nom":"Dead Cells","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/Users/x/Library/Application Support/Cidre/games/588650","taille":2145895956,"dernier_lancement":0}
    ]
    """

private let infoJSON = """
    {"appid":552500,"nom":"Warhammer: Vermintide 2","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"wrapper":true,"chemin":"/jeux/vt2","taille":68863410968,"dernier_lancement":1791039401,"sauvegardes":true,"options":{"tso":true,"vsync":true,"hud":false,"async":true,"fils_compilation":4,"eac_untrusted":true,"luajit":true}}
    """

@Test func decodeLaListe() throws {
    let games = try JSONDecoder().decode([Game].self, from: Data(listJSON.utf8))
    #expect(games.map(\.appid) == [464920, 552500, 588650])

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
    #expect(info.savesSynced)
    #expect(info.options.asyncShaders)
    #expect(info.options.compilerThreads == 4)
    #expect(info.options.eacUntrusted)
    #expect(info.options.luajit)
    #expect(info.options.tso)
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
        esac
        """.write(to: script, atomically: true, encoding: .utf8)

    let cli = try #require(CidreCLI.locate(userChoice: script.path, environment: [:], home: dir))
    #expect(try await cli.list().count == 3)

    await #expect(throws: CidreError.self) { try await cli.info(appid: 42) }

    let log = dir.appendingPathComponent("logs/play.log")
    try await cli.play(appid: 7, log: log)
    #expect(try String(contentsOf: log, encoding: .utf8) == "lancement 7\n")
}
