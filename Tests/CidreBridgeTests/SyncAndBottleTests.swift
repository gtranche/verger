import Foundation
import Testing

@testable import CidreBridge

/// Les champs que Cidre 1.5.9 ajoute : la methode de synchro des sauvegardes
/// (`synchro`) et les jeux trouves dans une bouteille (`source = "bouteille"`).
/// Un Cidre plus ancien ne les ecrit pas : le decodage doit rester valide.
struct SyncAndBottleTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func saveStatusLinkedToSteam() throws {
        let s = try decode(SaveStatus.self, """
        {"id":"3527290","configure":true,"etat":"steam","steam":"lien","lie":true,"dossier":"/x","copie":"","icloud":false,"a_sauvegarder":0,"a_restaurer":0,"historique":1,"synchro":"steam_macos","synchro_detail":"Steam Cloud : dossier lié"}
        """)
        #expect(s.state == .steam)
        #expect(s.sync == "steam_macos")
        #expect(s.syncedBySteam)
        #expect(s.syncDetail == "Steam Cloud : dossier lié")
    }

    @Test func saveStatusCopiedByCidre() throws {
        let s = try decode(SaveStatus.self, """
        {"id":"1903340","configure":true,"etat":"jamais_sauvegarde","steam":"","dossier":"/x","copie":"/c","icloud":false,"a_sauvegarder":7,"a_restaurer":0,"historique":0,"synchro":"copie","synchro_detail":"Copie Cidre"}
        """)
        #expect(s.state == .neverBackedUp)
        #expect(!s.syncedBySteam)
        #expect(s.sync == "copie")
    }

    @Test func saveStatusFromOlderCidre() throws {
        let s = try decode(SaveStatus.self, """
        {"id":"1","configure":true,"etat":"a_jour","dossier":"/x","copie":"/c","icloud":true,"a_sauvegarder":0,"a_restaurer":0,"historique":0}
        """)
        #expect(s.sync == nil)
        #expect(!s.syncedBySteam)
        #expect(s.onICloud)
    }

    @Test func ownedGameInBottle() throws {
        let g = try decode(OwnedGame.self, """
        {"appid":945360,"nom":"Among Us","plateformes":["windows"],"installe":false,"source":"bouteille","origine":"crossover","bouteille":"Steam","chemin":"/b/Among Us","buildid":12547701,"taille":656300821}
        """)
        #expect(g.inBottle)
        #expect(g.origin == "crossover")
        #expect(g.bottle == "Steam")
        #expect(g.sizeBytes == 656_300_821)
    }

    @Test func ownedGameWithoutBottleFields() throws {
        let g = try decode(OwnedGame.self, """
        {"appid":1,"nom":"X","plateformes":["windows","macos"],"installe":true}
        """)
        #expect(!g.inBottle)
        #expect(g.bottle == nil)
    }
}
