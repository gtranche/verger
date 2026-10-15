import Foundation
import Testing

@testable import CidreBridge

// `cidre info 1903340 --json` (Expedition 33) sur un M4, notes raccourcies :
// la fiche dit DXMT partout ; sur M2 et suivants, DXMT argent et D3D12 bronze.
private let infoM4JSON = """
    {"id":"1903340","appid":1903340,"nom":"Clair Obscur: Expedition 33","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"wrapper":true,"chemin":"/jeux/e33","taille":1,"dernier_lancement":0,"sauvegardes":true,"options":{},"options_perso":{},"maj":null,
     "fiche":{"jeu":{"appid":1903340},"cidre":{"d3d11":"dxmt"},
      "compat":{"pour":"M2 et suivants","voie":"dxmt","etat":"argent","source":"cidre-test","date":"2026-10-12","machine":"iMac M4 24 Go","cidre_version":"1.5.3","fps_menu":77,"fps_jeu":35,"notes":"DXMT, Moyen 50 %."},
      "reglages_jeu":[],"variantes":["coeurs_gpu >= 1"],
      "compat_reference":{"etat":"argent","source":"cidre-test","machine":"M1 Max 32 Go","fps_menu":130,"fps_jeu":52,"voie":"dxmt"},
      "compat_machines":[
       {"nom":"M1","si":"famille_gpu <= 7","voie":"d3d12","etat":"ko","options":"dx12=true sm66=true","notes":"Pas d'atomiques 64 bits.","applique":false},
       {"nom":"M2 et suivants","si":"famille_gpu >= 8","voie":"dxmt","etat":"argent","fps_menu":77,"fps_jeu":35,"applique":true},
       {"nom":"M2 et suivants","si":"famille_gpu >= 8","voie":"d3d12","etat":"bronze","fps_jeu":19,"options":"dx12=true sm66=true","applique":true}],
      "rapports":1}}
    """

@Test func decodeLaCompatibiliteParFamille() throws {
    let info = try JSONDecoder().decode(GameInfo.self, from: Data(infoM4JSON.utf8))
    let compat = try #require(info.compatibility)
    let here = try #require(compat.here)
    #expect(here.verdict == .silver && here.route?.rawValue == "dxmt" && here.scope == "M2 et suivants")
    #expect(here.fpsMenu == 77 && here.fpsGame == 35 && here.machine == "iMac M4 24 Go")
    #expect(compat.reference?.machine == "M1 Max 32 Go" && compat.reference?.fpsGame == 52)
    #expect(compat.families.count == 3)
    // ici, le D3D12 est une autre voie possible ; le M1 est ailleurs
    #expect(compat.otherRoutesHere.map(\.verdict) == [.bronze])
    #expect(compat.otherRoutesHere.first?.options == "dx12=true sm66=true")
    #expect(compat.elsewhere.map(\.name) == ["M1"] && compat.elsewhere.first?.verdict == .broken)
    #expect(compat.otherRoutesHere.first?.route?.title == "Direct3D 12")
}

@Test func compatibiliteDUnCidreDAvantLesFamilles() throws {
    // Cidre <= 1.5.11 : "compat" seul ; pas de fiche : null ; fiche sans [compat] : {}
    let ancien = infoM4JSON.replacingOccurrences(of: #""compat_reference":"#, with: #""x":"#)
        .replacingOccurrences(of: #""compat_machines":"#, with: #""y":"#)
    let compat = try #require(try JSONDecoder().decode(GameInfo.self, from: Data(ancien.utf8)).compatibility)
    #expect(compat.here?.verdict == .silver && compat.reference == nil && compat.families.isEmpty)
    #expect(compat.otherRoutesHere.isEmpty && compat.elsewhere.isEmpty)

    let sansFiche = #"{"appid":1,"nom":"X","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"chemin":"/x","fiche":null}"#
    #expect(try JSONDecoder().decode(GameInfo.self, from: Data(sansFiche.utf8)).compatibility == nil)
    let ficheVide = #"{"appid":1,"nom":"X","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"chemin":"/x","fiche":{"jeu":{},"cidre":{},"compat":{},"reglages_jeu":[],"variantes":[],"rapports":0}}"#
    #expect(try JSONDecoder().decode(GameInfo.self, from: Data(ficheVide.utf8)).compatibility == nil)
    // un etat inconnu se lit « non teste », sans faire tomber la fiche
    let inconnu = #"{"appid":1,"nom":"X","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"chemin":"/x","fiche":{"compat":{"etat":"platine","notes":"?"}}}"#
    #expect(try JSONDecoder().decode(GameInfo.self, from: Data(inconnu.utf8)).compatibility?.here?.verdict == .untested)
}

@Test func leRapportDitLaFamilleEtLaVoie() {
    var options = LaunchOptions()
    options.dx12 = true
    options.d3d11 = "dxmt"
    let report = GameReport(date: "2026-10-15", context: .init(machine: "M4 24 Go", options: options, gpuFamily: 9), verdict: .bronze, fpsGame: 19)
    #expect(report.toml == "[[rapports]]\ndate = \"2026-10-15\"\nmachine = \"M4 24 Go\"\nfamille_gpu = 9\nvoie = \"d3d12\"\netat = \"bronze\"\nfps_jeu = 19\n")
    options.dx12 = false
    #expect(GameReport.Context(options: options).route == "dxmt")
    options.d3d11 = nil
    options.dx12 = nil
    #expect(GameReport.Context(options: options).route == nil && GameReport.Context().route == nil)
}
