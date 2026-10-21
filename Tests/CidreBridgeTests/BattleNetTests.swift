import Foundation
import Testing

@testable import CidreBridge

// Sortie reelle de `cidre list --json` pour un jeu Battle.net (Cidre 9898da3).
private let bnetJSON = """
    [{"id":"bnet-osi","appid":null,"nom":"Diablo II: Resurrected","plateforme":"windows","lancement":"cidre","source":"battlenet","installe":true,"wrapper":null,"chemin":"/Users/x/Dev/pfx-battlenet/drive_c/Program Files (x86)/Diablo II Resurrected","taille":30575169536,"dernier_lancement":0,"emplacement":null,"en_ligne":true,"deplacement":null,"mac_32bits":null},
     {"id":"bnet-fen","appid":null,"nom":"Diablo IV","plateforme":"windows","lancement":"cidre","source":"battlenet","installe":true,"wrapper":null,"chemin":"/Volumes/SSK/Diablo IV","taille":0,"dernier_lancement":0,"emplacement":null,"en_ligne":false,"deplacement":null,"mac_32bits":null},
     {"id":"x-1","appid":null,"nom":"Source a venir","plateforme":"windows","lancement":"cidre","source":"epic","installe":true,"wrapper":null,"chemin":"/x","taille":0,"dernier_lancement":0}]
    """

@Test func decodeLesJeuxBattleNet() throws {
    let games = try JSONDecoder().decode([Game].self, from: Data(bnetJSON.utf8))
    let d2r = games[0]
    #expect(d2r.id == "bnet-osi")
    #expect(d2r.appid == nil)
    #expect(d2r.source == .battlenet)
    #expect(d2r.launch == .cidre)
    #expect(d2r.sizeBytes == 30_575_169_536)
    #expect(d2r.playable)
    // pas de wrapper Steam a reclamer pour un jeu Battle.net
    #expect(!d2r.wrapperMissing)

    let d4 = games[1]
    #expect(d4.source == .battlenet)
    #expect(!d4.online)
    #expect(!d4.playable)

    // une source que ce Verger ne connait pas : hors Steam, jamais Steam
    #expect(games[2].source == .local)
}

@Test func decodeLEtatDuClientBattleNet() throws {
    let json = #"{"prefixe":"/p/pfx-battlenet","installe":true,"ouvert":true,"pour":"bnet-osi","jeu":"D2R.exe","jeux":2}"#
    let status = try JSONDecoder().decode(BattleNetStatus.self, from: Data(json.utf8))
    #expect(status.installed && status.open)
    #expect(status.openFor == "bnet-osi")
    #expect(status.runningGame == "D2R.exe")
    #expect(status.gameCount == 2)

    let ferme = #"{"prefixe":"/p","installe":false,"ouvert":false,"pour":null,"jeu":null,"jeux":0}"#
    let absent = try JSONDecoder().decode(BattleNetStatus.self, from: Data(ferme.utf8))
    #expect(!absent.installed && !absent.open && absent.openFor == nil && absent.runningGame == nil)
}

/// Sur une fausse CLI : `cidre battlenet etat --json` et `cidre battlenet ouvrir`.
@Test func piloteLeClientBattleNet() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("cidre")
    try """
        #!/bin/sh
        case "$1 $2" in
          "battlenet etat") echo '{"prefixe":"/p","installe":true,"ouvert":false,"pour":null,"jeu":null,"jeux":1}' ;;
          "battlenet ouvrir") echo "ouvert" >> "$(dirname "$0")/appels.txt" ;;
          *) echo "inconnu : $*" >&2; exit 2 ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)
    let cli = try #require(CidreCLI.locate(userChoice: script.path, environment: [:], home: dir))
    let status = try await cli.battleNetStatus()
    #expect(status.installed && !status.open && status.gameCount == 1)
    try await cli.openBattleNet()
    let appels = try String(contentsOf: dir.appendingPathComponent("appels.txt"), encoding: .utf8)
    #expect(appels == "ouvert\n")
}
