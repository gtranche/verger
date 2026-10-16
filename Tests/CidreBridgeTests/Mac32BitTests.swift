import Foundation
import Testing

@testable import CidreBridge

// Une version macOS 32 bits seulement (Fahrenheit Remastered, Portal 2...) :
// macOS ne la lance plus depuis Catalina, et Rosetta 2 ne traduit pas le 32
// bits. Cidre la signale par "mac_32bits" ; Verger traite le jeu en Windows.

@Test func uneVersionMac32BitsNEstPasUneVersionMac() throws {
    let json = """
        [{"appid":312840,"nom":"Fahrenheit: Indigo Prophecy Remastered","plateformes":["windows","macos"],"mac_32bits":true,"installe":false},
         {"appid":464920,"nom":"Surviving Mars","plateformes":["windows","macos"],"installe":false},
         {"appid":34440,"nom":"Civilization IV","plateformes":["macos"],"mac_32bits":true,"installe":false}]
        """
    let owned = try JSONDecoder().decode([OwnedGame].self, from: Data(json.utf8))
    // Fahrenheit : pas de « Version macOS (par Steam) », la version Windows par Cidre
    #expect(owned[0].isMac32Bit && !owned[0].hasMac && owned[0].hasWindows)
    // un Cidre d'avant ce champ, ou une vraie version 64 bits : rien ne change
    #expect(!owned[1].isMac32Bit && owned[1].hasMac)
    // Mac 32 bits sans Windows : ni l'un ni l'autre
    #expect(owned[2].isMac32Bit && !owned[2].hasMac && !owned[2].hasWindows)
}

@Test func unJeuInstalleEnMac32BitsDemandeLaVersionWindows() throws {
    let json = """
        [{"id":"312840","appid":312840,"nom":"Fahrenheit","plateforme":"macos","lancement":"cidre","source":"steam","installe":true,"wrapper":false,"chemin":"/s/312840","taille":1,"dernier_lancement":0,"emplacement":null,"en_ligne":true,"deplacement":null,"mac_32bits":true},
         {"id":"464920","appid":464920,"nom":"Surviving Mars","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"wrapper":false,"chemin":"/s/464920","taille":1,"dernier_lancement":0,"mac_32bits":false},
         {"id":"588650","appid":588650,"nom":"Dead Cells","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/c/588650","taille":1,"dernier_lancement":0,"mac_32bits":null},
         {"id":"620","appid":620,"nom":"Portal 2","plateforme":"macos","lancement":"natif","source":"steam","installe":true,"wrapper":false,"chemin":"/s/620","taille":1,"dernier_lancement":0}]
        """
    let games = try JSONDecoder().decode([Game].self, from: Data(json.utf8))
    #expect(games[0].mac32Bit && games[0].needsWindowsVersion && !games[0].playable)
    #expect(games[0].launch == .cidre)
    #expect(!games[1].needsWindowsVersion && games[1].playable && games[1].launch == .native)
    #expect(!games[2].mac32Bit && games[2].playable)
    // un Cidre d'avant ce champ : comme avant
    #expect(!games[3].mac32Bit && games[3].playable)
}

@Test func lancerUneVersionMac32BitsEstRefuse() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("cidre")
    try """
        #!/bin/sh
        case "$1" in
          play) m="Fahrenheit : Sa version Mac n'existe qu'en 32 bits : macOS ne la lance plus depuis Catalina (Rosetta 2 ne traduit pas le 32 bits). Cidre installe la version Windows (cidre dl 312840)."
                case " $* " in *" --json "*) printf '{"evenement":"erreur","code":"mac_32bits","message":"%s"}\\n' "$m" ;; esac
                echo "$m" >&2; exit 9 ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)
    let cli = try #require(CidreCLI.locate(userChoice: script.path, environment: [:], home: dir))
    let log = dir.appendingPathComponent("play.log")
    do {
        try await cli.play(id: "312840", log: log)
        Issue.record("le lancement aurait du etre refuse")
    } catch let CidreError.refused(message) {
        #expect(message.contains("32 bits") && message.contains("cidre dl 312840"))
    }
    // l'evenement --json
    let line = #"{"evenement":"erreur","code":"mac_32bits","message":"Version Mac 32 bits"}"#
    #expect(PlayEvent.parse(line: line) == .refused(code: "mac_32bits", message: "Version Mac 32 bits"))
}

@Test func leMessageMac32BitsEstTraduit() {
    #expect(Game.mac32BitNotice.contains("32"))
}
