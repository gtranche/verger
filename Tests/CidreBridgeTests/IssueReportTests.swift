import Foundation
import Testing

@testable import CidreBridge

@Test func retireCeQuiIdentifieLUtilisateur() {
    let a = Anonymizer(user: "marie", steamAccount: "mariedu42", hostNames: ["MacBook-Pro-de-Marie.local", "MacBook-Pro-de-Marie"])
    let brut = """
        === 2026-10-05 08:16:52  appid=588650  jeu=deadcells.exe
            dossier : /Users/marie/Library/Application Support/Cidre/games/588650
        File 'Z:\\Users\\marie\\Library\\Steam\\x.dll' is signed ; C:\\users\\marie\\AppData\\Roaming\\Jeu
        Steam_SetMinidumpSteamID:  Caching Steam ID:  76561198043440982 [API loaded no]
        Logging in user 'mariedu42' [U:1:83175254] to Steam Public...OK
        userdata/83175254/config/localconfig.vdf
        Game mode enablement policy set to \u{1B}[0;33mauto\u{1B}[0;0m. puis [0;33mauto[0;0m
        hote MacBook-Pro-de-Marie.local, contact marie.dupont@exemple.fr
        /Users/mariette/autre et la marie du texte courant
        """
    let net = a.clean(brut)
    for secret in ["/Users/marie/", "\\Users\\marie\\", "users\\marie\\", "76561198043440982", "83175254", "mariedu42", "MacBook-Pro-de-Marie", "marie.dupont", "[0;33m", "\u{1B}"] {
        #expect(!net.contains(secret), "reste : \(secret)")
    }
    #expect(net.contains("/Users/…/Library/Application Support/Cidre/games/588650"))
    #expect(net.contains("Z:\\Users\\…\\Library\\Steam\\x.dll"))
    #expect(net.contains("Caching Steam ID:  7656119… [API loaded no]"))
    #expect(net.contains("Logging in user '‹steam›' [U:1:…]"))
    #expect(net.contains("policy set to auto. puis auto"))
    // ce qui n'identifie personne reste : l'appid, un autre nom, le mot dans une phrase
    #expect(net.contains("appid=588650"))
    #expect(net.contains("/Users/mariette/autre et la marie du texte courant"))
}

@Test func prepareUnIncidentQuiTientDansUneAdresse() throws {
    let lines = (1...400).map { "ligne \($0) : info: DXVK é + & # % — un peu de texte pour peser" }
    let report = IssueReport(
        repository: "gtranche/cidre", title: "Dead Cells : écran noir + son",
        text: "**Ce qui s'est passé**\n\n(à compléter)\n\n**Environnement**\n- Verger 0.3.5 · Cidre 1.4.2",
        logTitle: "Fin du journal", log: lines)

    // le texte complet porte tout le journal
    #expect(report.body().contains("ligne 1 :") && report.body().contains("ligne 400 :"))

    let url = report.url()
    #expect(url.absoluteString.utf8.count <= 7000)
    #expect(url.absoluteString.hasPrefix("https://github.com/gtranche/cidre/issues/new?"))
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.first { $0.name == "title" }?.value == "Dead Cells : écran noir + son")
    let body = try #require(items.first { $0.name == "body" }?.value)
    // la FIN du journal est gardee, le debut part en piece jointe
    #expect(body.contains("ligne 400 :") && !body.contains("ligne 1 :"))
    #expect(body.hasPrefix("**Ce qui s'est passé**"))
    #expect(body.contains("é + & # % —"))
    // le `+` voyage encode, sinon GitHub le lirait comme un espace
    #expect(!url.absoluteString.contains("+"))

    // sans journal, ou avec une limite trop courte pour en porter : le texte seul
    #expect(IssueReport(repository: "gtranche/verger", title: "t", text: "x").body() == "x")
    let tight = report.url(maxLength: 400)
    #expect(URLComponents(url: tight, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value == report.text)
}

@Test func decritCeMac() {
    // les noms du Mac se lisent sur place, sans attendre le reseau
    let started = Date()
    #expect(!Anonymizer.localHostNames().isEmpty)
    #expect(Date().timeIntervalSince(started) < 0.5)
    let info = SystemInfo.current
    #expect(!info.macOS.isEmpty && !info.model.isEmpty && info.memoryGB > 0)
    #expect(info.summary.contains("macOS \(info.macOS)"))
}

/// Un vrai journal de cette machine, nettoye : plus rien n'y identifie l'utilisateur.
///   VERGER_ESSAI_JOURNAL=/chemin/vers/cidre Scripts/test.sh --filter leVraiJournalEstNettoye
@Test(.enabled(if: ProcessInfo.processInfo.environment["VERGER_ESSAI_JOURNAL"] != nil))
func leVraiJournalEstNettoye() async throws {
    let cli = CidreCLI(executable: URL(fileURLWithPath: ProcessInfo.processInfo.environment["VERGER_ESSAI_JOURNAL"]!))
    let status = try await cli.status()
    let anonymizer = Anonymizer.current(steamAccount: status.steamAccount)
    for id in ["588650", "552500"] {
        let raw = try await cli.log(id: id, lines: 4000)
        let clean = raw.map(anonymizer.clean)
        let joined = clean.joined(separator: "\n")
        let leaks = ([NSUserName(), status.steamAccount ?? "\u{0}", "7656119804"] + Anonymizer.localHostNames())
            .filter { !$0.isEmpty && joined.range(of: $0, options: .caseInsensitive) != nil }
        let url = IssueReport(repository: "gtranche/cidre", title: "essai", text: "texte", logTitle: "Fin du journal", log: clean).url()
        print("\(id) : \(raw.count) lignes, \(raw.joined().utf8.count / 1024) Kio ; adresse de \(url.absoluteString.utf8.count) octets ; fuites : \(leaks.count)")
        #expect(leaks.isEmpty, "reste dans le journal de \(id)")
        #expect(url.absoluteString.utf8.count <= 7000)
    }
}
