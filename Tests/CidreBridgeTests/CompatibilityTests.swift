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
    let report = GameReport(date: "2026-10-15", context: .init(machine: "M4 24 Go", model: "Mac16,2", macOS: "27.0.1", options: options, gpuFamily: 9),
                            verdict: .bronze, fpsGame: 19)
    #expect(report.toml == "[[rapports]]\ndate = \"2026-10-15\"\nmachine = \"M4 24 Go\"\nmodele = \"Mac16,2\"\nmacos_version = \"27.0.1\"\nfamille_gpu = 9\nvoie = \"d3d12\"\netat = \"bronze\"\nfps_jeu = 19\n")
    options.dx12 = false
    #expect(GameReport.Context(options: options).route == "dxmt")
    options.d3d11 = nil
    options.dx12 = nil
    #expect(GameReport.Context(options: options).route == nil && GameReport.Context().route == nil)
}

// `cidre info 2358720 --json` juste apres `cidre dl` : le jeu n'a pas de fiche
// dans la base, Cidre en a ecrit une provisoire avec le resume ProtonDB.
private let infoProvisoireJSON = """
    {"appid":2358720,"nom":"Black Myth: Wukong","plateforme":"windows","lancement":"cidre","source":"cidre","installe":true,"chemin":"/jeux/bmw",
     "fiche":{"jeu":{"appid":2358720,"nom":"Black Myth: Wukong","plateformes_steam":"windows","provisoire":true},"cidre":{},
      "compat":{"etat":"non-teste","date":"2026-10-15"},
      "protondb":{"palier":"gold","tendance":"gold","meilleur_palier":"platinum","confiance":"strong","rapports":209,"score":81,"source":"protondb","date":"2026-10-15","url":"https://www.protondb.com/app/2358720"},
      "reglages_jeu":[],"variantes":[],"compat_reference":{"etat":"non-teste","date":"2026-10-15"},"compat_machines":[],"origine":"provisoire","rapports":0}}
    """

@Test func uneFicheProvisoireMontreLeResumeProtonDB() throws {
    let compat = try #require(try JSONDecoder().decode(GameInfo.self, from: Data(infoProvisoireJSON.utf8)).compatibility)
    #expect(compat.provisional && compat.here == nil && compat.families.isEmpty)
    let p = try #require(compat.protonDB)
    #expect(p.tier == .gold && p.trendingTier == .gold && p.bestTier == .platinum)
    #expect(p.reports == 209 && p.confidence == "strong")
    #expect(p.url?.absoluteString == "https://www.protondb.com/app/2358720")
}

@Test func leResumeProtonDBDUneFicheDeLaBase() throws {
    // une fiche du catalogue : origine cache, palier ProtonDB ; une autre sans
    // palier (nourrie par l'export seul) : rien a montrer de ProtonDB
    let cache = infoProvisoireJSON.replacingOccurrences(of: #""origine":"provisoire""#, with: #""origine":"cache""#)
    let compat = try #require(try JSONDecoder().decode(GameInfo.self, from: Data(cache.utf8)).compatibility)
    #expect(!compat.provisional && compat.protonDB?.tier == .gold)
    let sansPalier = infoProvisoireJSON.replacingOccurrences(of: #""palier":"gold","#, with: "")
        .replacingOccurrences(of: #""origine":"provisoire""#, with: #""origine":"cache""#)
    #expect(try JSONDecoder().decode(GameInfo.self, from: Data(sansPalier.utf8)).compatibility == nil)
    // un palier inconnu ne fait pas tomber le reste de la fiche : il ne se montre pas
    let inconnu = infoM4JSON.replacingOccurrences(of: #""reglages_jeu":[]"#,
                                                  with: #""protondb":{"palier":"mithril","rapports":3},"reglages_jeu":[]"#)
    let c2 = try #require(try JSONDecoder().decode(GameInfo.self, from: Data(inconnu.utf8)).compatibility)
    #expect(c2.protonDB == nil && c2.here?.verdict == .silver && !c2.provisional)
    #expect(GameCompatibility.ProtonDBTier.platinum.title == "Platine")
}

// `cidre info 1245620 --json` (ELDEN RING), fiche du catalogue : [jeu] importe de
// PCGamingWiki et blocs PCGamingWiki, AppleGamingWiki et CrossOver.
private let infoImporteJSON = """
    {"appid":1245620,"nom":"ELDEN RING","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"chemin":"/jeux/er",
     "fiche":{"jeu":{"appid":1245620,"nom":"ELDEN RING","plateformes_steam":"windows","api":"d3d12","api_disponibles":"d3d12","bits":64,"anticheat":"eac","drm":"steam"},
      "cidre":{"exe_sans_anticheat":"eldenring.exe"},"compat":{"etat":"non-teste","date":"2026-10-11"},
      "protondb":{"palier":"gold","rapports":2105,"source":"protondb","date":"2026-10-01","url":"https://www.protondb.com/app/1245620"},
      "pcgamingwiki":{"fichiers_reglages":"AppData/Roaming/EldenRing/GraphicsConfig.xml","sauvegardes":"AppData/Roaming/EldenRing/<uid>/ ; jeu:save","correspondance":"appid","source":"pcgamingwiki","date":"2026-10-11","url":"https://www.pcgamingwiki.com/wiki/Elden_Ring"},
      "applegamingwiki":{"crossover":"jouable","wine":"parfait","parallels":"ko","rosetta":"inconnu","methodes":"crossover","dernier_temoignage":"2025-05-12","source":"applegamingwiki","date":"2026-10-11","url":"https://www.applegamingwiki.com/wiki/Elden_Ring"},
      "crossover":{"recette":"com.codeweavers.c4.18041","bouteille":"win10_64","graphismes":"d3dmetal","crossover_version":"23.5","recette_date":"2026-06-30","source":"crossover","date":"2026-10-13","url":"https://www.codeweavers.com/compatibility/browse/name/?app_id=18041"},
      "jeu_sources":{"api":"pcgamingwiki 2026-10-11","api_disponibles":"pcgamingwiki 2026-10-11","bits":"pcgamingwiki 2026-10-11","anticheat":"pcgamingwiki 2026-10-11","drm":"pcgamingwiki 2026-10-11"},
      "reglages_jeu":[],"variantes":[],"compat_reference":{"etat":"non-teste"},"compat_machines":[],"origine":"cache","rapports":0}}
    """

@Test func lesAutresSourcesDeLaFiche() throws {
    let compat = try #require(try JSONDecoder().decode(GameInfo.self, from: Data(infoImporteJSON.utf8)).compatibility)
    let e = try #require(compat.external)
    #expect(e.antiCheat == .init(id: "eac", name: "Easy Anti-Cheat", source: "pcgamingwiki 2026-10-11"))
    #expect(e.antiCheat?.blocksOnline == true)
    #expect(e.apis == .init(value: "Direct3D 12", source: "pcgamingwiki 2026-10-11"))
    #expect(e.bits?.value == "64 bits" && e.engine == nil && e.drm?.value == "steam")
    // un verdict inconnu (« inconnu ») est laisse de cote, l'ordre est celui des voies
    let agw = try #require(e.appleGamingWiki)
    #expect(agw.verdicts.map(\.route) == [.crossover, .wine, .parallels])
    #expect(agw.verdicts.map(\.verdict) == [.playable, .perfect, .broken])
    #expect(agw.lastReport == "2025-05-12" && agw.url?.host == "www.applegamingwiki.com")
    #expect(e.crossOver?.graphics == "d3dmetal" && e.crossOver?.bottle == "win10_64" && e.crossOver?.dllOverrides == nil)
    #expect(e.pcGamingWiki?.settingsFiles == ["AppData/Roaming/EldenRing/GraphicsConfig.xml"])
    #expect(e.pcGamingWiki?.saves == ["AppData/Roaming/EldenRing/<uid>/", "jeu:save"])
}

@Test func autresSourcesAbsentesOuIllisibles() throws {
    // Cidre d'avant (pas de blocs importes) : seul le [jeu] compte
    let ancien = infoImporteJSON
        .replacingOccurrences(of: #""pcgamingwiki":{"#, with: #""x1":{"#)
        .replacingOccurrences(of: #""applegamingwiki":{"#, with: #""x2":{"#)
        .replacingOccurrences(of: #""crossover":{"recette""#, with: #""x3":{"recette""#)
        .replacingOccurrences(of: #""jeu_sources":{"#, with: #""x4":{"#)
    let e = try #require(try JSONDecoder().decode(GameInfo.self, from: Data(ancien.utf8)).compatibility?.external)
    #expect(e.appleGamingWiki == nil && e.crossOver == nil && e.pcGamingWiki == nil)
    #expect(e.antiCheat?.source == nil && e.apis?.value == "Direct3D 12")
    // null partout, anti-triche « none », moteur « autre » sans nom : rien a montrer
    let rien = #"{"appid":1,"nom":"X","plateforme":"windows","lancement":"cidre","source":"steam","installe":true,"chemin":"/x","fiche":{"jeu":{"appid":1,"anticheat":"none","moteur":"autre"},"compat":{},"protondb":null,"pcgamingwiki":null,"applegamingwiki":null,"crossover":null,"jeu_sources":{}}}"#
    #expect(try JSONDecoder().decode(GameInfo.self, from: Data(rien.utf8)).compatibility == nil)
    // un moteur nomme par PCGamingWiki passe avant le vocabulaire de la fiche
    let moteur = rien.replacingOccurrences(of: #""moteur":"autre""#, with: #""moteur":"autre","moteur_nom":"id Tech 4""#)
        .replacingOccurrences(of: #""jeu_sources":{}"#, with: #""jeu_sources":{"moteur_nom":"pcgamingwiki 2026-10-15"}"#)
    let m = try JSONDecoder().decode(GameInfo.self, from: Data(moteur.utf8)).compatibility?.external?.engine
    #expect(m == .init(value: "id Tech 4", source: "pcgamingwiki 2026-10-15"))
    // une valeur d'un autre type (nombre au lieu de chaine) ne fait pas tomber la fiche
    let nombre = rien.replacingOccurrences(of: #""anticheat":"none""#, with: #""anticheat":3"#)
    #expect(try JSONDecoder().decode(GameInfo.self, from: Data(nombre.utf8)).compatibility?.external?.antiCheat?.name == "3")
}
