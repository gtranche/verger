import Foundation
import Testing

@testable import CidreBridge

/// Les images d'un jeu Battle.net, prises dans le cache du client (un faux
/// prefixe : memes index JSON et memes chemins Cache/ab/cd/<md5> que le vrai).
struct BattleNetArtTests {
    private func fakePrefix() throws -> URL {
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent("bnet-art-\(UUID().uuidString)")
        let cache = prefix.appendingPathComponent("drive_c/users/joueur/AppData/Local/Battle.net/Cache")
        func put(_ hash: String, _ data: Data, date: Date? = nil) throws {
            let dir = cache.appendingPathComponent(String(hash.prefix(2))).appendingPathComponent(String(hash.dropFirst(2).prefix(2)))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(hash)
            try data.write(to: file)
            if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path) }
        }
        let oldArt = String(repeating: "a", count: 32), newArt = String(repeating: "b", count: 32)
        let gone = String(repeating: "c", count: 32), background = String(repeating: "d", count: 32)
        try put(oldArt, Data("ancienne".utf8))
        try put(newArt, Data("nouvelle".utf8))
        try put(background, Data("fond".utf8))
        // un ancien index, puis un recent ; un index qui pointe une image partie du cache
        try put("11" + String(repeating: "0", count: 30), Data("""
        {"files":{"default":{"osi#OSI_X2_KEY_ART":{"hash":"\(oldArt)","name":"a.jpg"},"osi_cn#OSI_KEY_ART_CN":{"hash":"\(newArt)","name":"cn.png"}}}}
        """.utf8), date: Date(timeIntervalSince1970: 1_000))
        try put("22" + String(repeating: "0", count: 30), Data("""
        {"files":{"default":{"osi#OSI_X2_KEY_ART":{"hash":"\(newArt)","name":"b.jpg"},"fenris#FENRIS_KEY_ART":{"hash":"\(gone)","name":"d4.jpg"},"fenris#FENRIS_INSTALL_BACKGROUND":{"hash":"\(background)","name":"bg.jpg"},"osi#OSI_ICON_SVG":{"name":"icon.svg"}},"koKR":{}}}
        """.utf8), date: Date(timeIntervalSince1970: 2_000))
        return prefix
    }

    @Test func codesAndPrefix() {
        #expect(BattleNetArt.code(of: "bnet-osi") == "osi")
        #expect(BattleNetArt.code(of: "1245620") == nil)
        #expect(BattleNetArt.product(of: "fen") == "fenris")
        #expect(BattleNetArt.steamAppIDs["fen"] == 2_344_520)
        #expect(BattleNetArt.prefix(ofGamePath: "/x/pfx-battlenet/drive_c/Program Files (x86)/Diablo II Resurrected") == "/x/pfx-battlenet")
        #expect(BattleNetArt.prefix(ofGamePath: "/Volumes/SSK SSD/Jeux Cidre/Battle.net/Diablo II Resurrected") == nil)
    }

    @Test func keyArtFromTheClientCache() throws {
        let prefix = try fakePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        // la key art de l'index le plus recent, pas celle d'un autre produit (osi_cn)
        let osi = try #require(BattleNetArt.find(code: "osi", prefix: prefix.path))
        #expect(osi.isPortrait)
        #expect(try String(contentsOf: osi.file, encoding: .utf8) == "nouvelle")
        // key art absente du cache : le fond d'installation, en paysage
        let fen = try #require(BattleNetArt.find(code: "fen", prefix: prefix.path))
        #expect(!fen.isPortrait)
        #expect(try String(contentsOf: fen.file, encoding: .utf8) == "fond")
        #expect(BattleNetArt.find(code: "inconnu", prefix: prefix.path) == nil)
        #expect(BattleNetArt.find(code: "osi", prefix: "/nulle/part") == nil)
    }
}
