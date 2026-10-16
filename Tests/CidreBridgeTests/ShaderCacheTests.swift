import Foundation
import Testing

@testable import CidreBridge

/// Les shaders d'un jeu sur ce Mac : l'evenement `shaders` de `cidre play
/// --json` (ecrit avant le lancement) et le champ `"shaders"` de `cidre info
/// --json`. Un Cidre plus ancien n'ecrit ni l'un ni l'autre.
struct ShaderCacheTests {
    private let game = #"{"id":"1929610","appid":1929610,"nom":"Demonologist","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"wrapper":null,"chemin":"/x","taille":1,"dernier_lancement":0"#

    @Test func premierLancementAnnonce() throws {
        let line = #"{"evenement":"shaders","etat":"premier_lancement","raison":null,"voie":"dxmt","dernier":null,"cumul":null,"macos":null,"message":"Premier lancement : ..."}"#
        guard case let .shaders(status)? = PlayEvent.parse(line: line) else {
            Issue.record("evenement shaders non reconnu"); return
        }
        #expect(status.state == .firstLaunch)
        #expect(status.reason == nil)
        #expect(status.renderer == "dxmt")
        #expect(status.lastRun == nil)
        #expect(status.announcement?.isEmpty == false)
    }

    @Test func cacheInvalideParMacOS() throws {
        let line = #"{"evenement":"shaders","etat":"cache_invalide","raison":"macos","voie":"dxmt","dernier":1792144452,"cumul":3600,"macos":"25E00","message":"macOS a ete mis a jour"}"#
        guard case let .shaders(status)? = PlayEvent.parse(line: line) else {
            Issue.record("evenement shaders non reconnu"); return
        }
        #expect(status.state == .invalidated)
        #expect(status.reason == .macOS)
        #expect(status.lastRun == Date(timeIntervalSince1970: 1792144452))
        #expect(status.announcement != status.message)
    }

    @Test func enCacheRienADire() throws {
        let line = #"{"evenement":"shaders","etat":"en_cache","raison":null,"voie":"d3d12","dernier":1792144452,"cumul":3600,"macos":"25F84","message":null}"#
        guard case let .shaders(status)? = PlayEvent.parse(line: line) else {
            Issue.record("evenement shaders non reconnu"); return
        }
        #expect(status.announcement == nil)
    }

    @Test func etatEtRaisonDeDemain() throws {
        // un Cidre plus recent : rien ne tombe, la raison inconnue garde le message de Cidre
        let line = #"{"evenement":"shaders","etat":"cache_invalide","raison":"pilote","voie":"dxmt","message":"Le pilote a change."}"#
        guard case let .shaders(status)? = PlayEvent.parse(line: line) else {
            Issue.record("evenement shaders non reconnu"); return
        }
        #expect(status.reason == .other)
        #expect(status.announcement == "Le pilote a change.")
        guard case let .shaders(later)? = PlayEvent.parse(line: #"{"evenement":"shaders","etat":"compile_en_fond"}"#) else {
            Issue.record("evenement shaders non reconnu"); return
        }
        #expect(later.state == .unknown)
        #expect(later.announcement == nil)
    }

    @Test func ficheDuJeu() throws {
        let info = try JSONDecoder().decode(GameInfo.self, from: Data((game + #","shaders":{"etat":"en_cache","raison":null,"voie":"dxmt","dernier":null,"cumul":null,"macos":null,"message":null}}"#).utf8))
        #expect(info.shaders?.state == .cached)
        // Cidre <= 1.5.11, jeu macOS (null), ou etat illisible : pas de ligne Shaders
        #expect(try JSONDecoder().decode(GameInfo.self, from: Data((game + "}").utf8)).shaders == nil)
        #expect(try JSONDecoder().decode(GameInfo.self, from: Data((game + #","shaders":null}"#).utf8)).shaders == nil)
        #expect(try JSONDecoder().decode(GameInfo.self, from: Data((game + #","shaders":{"voie":3}}"#).utf8)).shaders == nil)
    }
}
