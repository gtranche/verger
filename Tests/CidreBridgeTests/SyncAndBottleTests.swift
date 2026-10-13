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

    // `cidre import --json` dit desormais ce qu'il a ramene des sauvegardes
    // de la bouteille, et `cidre saves --json` le redit sous "reprise".
    @Test func importResultWithSavesBroughtOver() throws {
        let r = try decode(ImportResult.self, """
        {"id":"2001","appid":2001,"nom":"Un Jeu","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/g/2001","taille":40995,"dernier_lancement":0,"reprise_sauvegardes":{"appid":2001,"etat":"copie","fichiers":3,"remplaces":1,"gardes":2,"identiques":0,"octets":17,"origine":"crossover","bouteille":"Jeux","depuis":"/b/users/crossover/AppData/LocalLow/S/P","vers":"/c/users/moi/AppData/LocalLow/S/P","dossier":"AppData/LocalLow/S/P","synchro":"copie","historique":"","date":1791926280,"message":"3 fichier(s) de sauvegarde ramené(s) de la bouteille « Jeux » (CrossOver)"}}
        """)
        let s = try #require(r.saves)
        #expect(s.state == .copied)
        #expect(s.files == 3)
        #expect(s.replaced == 1)
        #expect(s.kept == 2)
        #expect(s.origin == "crossover")
        #expect(s.bottle == "Jeux")
        #expect(s.from == "/b/users/crossover/AppData/LocalLow/S/P")
        #expect(s.to == "/c/users/moi/AppData/LocalLow/S/P")
        #expect(s.notice(game: "Un Jeu").contains("3"))
        #expect(s.notice(game: "Un Jeu").contains("Jeux"))
    }

    @Test func importResultWhenSavesCouldNotBeBroughtOver() throws {
        let r = try decode(ImportResult.self, """
        {"id":"2008","appid":2008,"nom":"X","reprise_sauvegardes":{"appid":2008,"etat":"erreur","raison":"prefixe_absent","message":"le disque C: de Cidre n'existe pas encore"}}
        """)
        #expect(r.saves?.state == .failed)
        #expect(r.saves?.files == 0)
        #expect(r.saves?.notice(game: "X").contains("le disque C: de Cidre n'existe pas encore") == true)
    }

    @Test func importResultFromOlderCidre() throws {
        // un Cidre plus ancien : la fiche du jeu seule
        let r = try decode(ImportResult.self, """
        {"id":"777","appid":777,"nom":"X","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true}
        """)
        #expect(r.saves == nil)
        #expect(try decode(ImportResult.self, #"{"id":"1","reprise_sauvegardes":null}"#).saves == nil)
    }

    // Steam d'abord : le dossier que Steam synchronise a deja des sauvegardes,
    // la bouteille ne les remplace pas.
    @Test func importResultWhenSteamComesFirst() throws {
        let r = try decode(ImportResult.self, """
        {"id":"2006","appid":2006,"nom":"Jeu Six","reprise_sauvegardes":{"appid":2006,"etat":"steam_prioritaire","fichiers":0,"remplaces":0,"gardes":2,"identiques":0,"octets":0,"origine":"crossover","bouteille":"Jeux","depuis":"/b","vers":"/m","dossier":"AppData/LocalLow/D/J","synchro":"steam_macos","historique":"","steam_fichiers":1,"steam_distants":false,"conflit_possible":false,"force":false,"date":1,"message":"m"}}
        """)
        let s = try #require(r.saves)
        #expect(s.state == .steamFirst)
        #expect(s.files == 0)
        #expect(s.kept == 2)
        #expect(s.steamFiles == 1)
        #expect(!s.possibleConflict)
        #expect(s.notice(game: "Jeu Six").contains("Steam Cloud"))
        #expect(s.notice(game: "Jeu Six").contains("Jeux"))
    }

    @Test func importResultFilledAnEmptySteamFolder() throws {
        let s = try decode(SavesImport.self, """
        {"appid":2014,"etat":"copie","fichiers":1,"remplaces":0,"gardes":0,"bouteille":"Jeux","synchro":"steam_macos","steam_fichiers":0,"steam_distants":false,"conflit_possible":true,"force":false}
        """)
        #expect(s.state == .copied)
        #expect(s.possibleConflict)
        let quiet = try decode(SavesImport.self, #"{"etat":"copie","fichiers":1,"bouteille":"Jeux"}"#)
        #expect(!quiet.possibleConflict)
        #expect(s.notice(game: "X") != quiet.notice(game: "X"))
    }

    @Test func importStatesAllHaveANotice() throws {
        for state in ["copie", "a_jour", "steam", "steam_prioritaire", "avec_le_jeu", "absentes", "introuvable", "erreur", "plus_tard"] {
            let s = try decode(SavesImport.self, #"{"etat":"\#(state)","bouteille":"B"}"#)
            #expect(s.notice(game: "Jeu").hasPrefix("Jeu"))
        }
        #expect(try decode(SavesImport.self, #"{"etat":"plus_tard"}"#).state == .unknown)
    }

    @Test func saveStatusCarriesWhatWasBroughtOver() throws {
        let s = try decode(SaveStatus.self, """
        {"id":"2007","configure":true,"etat":"jamais_sauvegarde","steam":"","dossier":"/x","copie":"/c","icloud":false,"local":{"fichiers":1,"octets":7,"modifie":1},"sauvegarde":{"fichiers":0,"octets":0,"modifie":0},"a_sauvegarder":1,"a_restaurer":0,"historique":0,"synchro":"copie","synchro_detail":"Copie Cidre","reprise":{"appid":2007,"etat":"copie","fichiers":1,"remplaces":0,"gardes":0,"identiques":0,"octets":7,"origine":"whisky","bouteille":"Ma Bouteille","depuis":"/b","vers":"/x","dossier":"Documents/My Games/Jeu Sept","synchro":"copie","historique":"","date":1,"message":"m"}}
        """)
        #expect(s.imported?.state == .copied)
        #expect(s.imported?.files == 1)
        #expect(s.imported?.origin == "whisky")
        let none = try decode(SaveStatus.self, """
        {"id":"7","configure":false,"synchro":"aucune","synchro_detail":"x","reprise":null}
        """)
        #expect(none.imported == nil)
    }

    @Test func ownedGameWithoutBottleFields() throws {
        let g = try decode(OwnedGame.self, """
        {"appid":1,"nom":"X","plateformes":["windows","macos"],"installe":true}
        """)
        #expect(!g.inBottle)
        #expect(g.bottle == nil)
    }
}
