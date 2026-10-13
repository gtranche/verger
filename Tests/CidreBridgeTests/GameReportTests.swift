import Foundation
import Testing

@testable import CidreBridge

@Test func ecritLeRapportAuFormatDesFiches() throws {
    var options = LaunchOptions()
    options.vsync = false
    options.compilerThreads = 6
    options.d3d11 = "dxmt"
    options.language = "fr"
    let report = GameReport(
        date: "2026-10-11",
        context: .init(machine: "M1 Max 32 Go", cidreVersion: "1.4.6", options: options, diagnostic: "== Verger ==\n  version : 0.3.10\n== Cidre ==\n  ok"),
        verdict: .gold, fpsMenu: 120, fpsGame: 45,
        notes: "Il dit \"ça marche\" ; chemin C:\\Jeu\nDeuxième ligne\ttab ")

    #expect(report.toml == """
        [[rapports]]
        date = "2026-10-11"
        machine = "M1 Max 32 Go"
        cidre_version = "1.4.6"
        etat = "or"
        fps_menu = 120
        fps_jeu = 45
        notes = "Il dit \\"ça marche\\" ; chemin C:\\\\Jeu\\nDeuxième ligne\\ttab"

        """)
    // le profil effectif, sous les noms de Cidre, les chaines entre guillemets
    let profile = try #require(report.profileToml)
    #expect(profile.hasPrefix("[profil]\ntso = true\nvsync = false\nhud = false\nasync = false\nfils_compilation = 6\n"))
    #expect(profile.contains("d3d11 = \"dxmt\"\nlangue = \"fr\"\n"))
    // les options que ce Cidre ne connait pas n'y sont pas
    #expect(!profile.contains("plein_ecran") && !profile.contains("metalfx"))

    // l'incident : titre fixe, formulaire du depot (c'est lui qui pose le label), le diagnostic en journal
    let issue = report.issue(gameName: "Dead Cells", gameID: "588650")
    #expect(issue.repository == "gtranche/cidre")
    #expect(issue.title == "Rapport de jeu : Dead Cells (588650)")
    #expect(issue.template == "rapport-jeu.yml" && issue.field == "rapport")
    let body = issue.body()
    #expect(body.hasPrefix("<!-- cidre-rapport v1 appid=588650 -->\n```toml\n[[rapports]]\n"))
    #expect(body.contains("```\n\n**Profil effectif**\n```toml\n[profil]\n"))
    #expect(body.contains("```text\n== Verger ==\n  version : 0.3.10\n== Cidre ==\n  ok\n```"))
    // l'adresse : le formulaire, le titre, et le rapport dans le champ du formulaire. Ni `labels=`
    // (GitHub rend une page 404 a qui n'a pas le droit de poser un label), ni `body=` (un formulaire l'ignore)
    let url = issue.url(maxLength: GameReport.maxURLLength, throughLogin: true)
    #expect(url.absoluteString.hasPrefix("https://github.com/gtranche/cidre/issues/new?template=rapport-jeu.yml&title=Rapport%20de%20jeu"))
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.map(\.name) == ["template", "title", "rapport"])
    #expect(items.first { $0.name == "title" }?.value == "Rapport de jeu : Dead Cells (588650)")
    #expect(items.first { $0.name == "rapport" }?.value == body)
    #expect(issue.delivery(maxLength: GameReport.maxURLLength, throughLogin: true) == .address(url, complete: true))
}

@Test func leRapportPasseAussiParLaConnexion() throws {
    // un joueur qui n'est pas connecte passe par /login?return_to=<adresse encodee une seconde fois> :
    // c'est cette forme, plus longue, qui doit tenir. Mesure sur github.com le 2026-10-13 :
    // « %C3%A9 » (6 octets) y devient « %25C3%25A9 » (10), « : / ? & = » trois octets chacun.
    let court = try #require(URL(string: "https://github.com/gtranche/cidre/issues/new?template=rapport-jeu.yml&title=t&rapport=%C3%A9"))
    #expect(IssueReport.length(of: court) == court.absoluteString.utf8.count)
    let parLaConnexion = "https://github.com/login?return_to=https%3A%2F%2Fgithub.com%2Fgtranche%2Fcidre%2Fissues%2Fnew%3Ftemplate%3Drapport-jeu.yml%26title%3Dt%26rapport%3D%25C3%25A9"
    #expect(IssueReport.length(of: court, throughLogin: true) == parLaConnexion.utf8.count)

    // un long diagnostic : coupe par la fin, et l'adresse tient meme par la connexion
    let lines = (1...400).map { "ligne \($0) : é è « diagnostic » + & # = un peu de texte pour peser" }
    let report = GameReport(date: "2026-10-13", context: .init(machine: "M1 Max 32 Go", cidreVersion: "1.5.10", options: LaunchOptions(),
                                                              diagnostic: lines.joined(separator: "\n")),
                            verdict: .silver, fpsGame: 40, notes: "Quelques saccades.")
    let issue = report.issue(gameName: "Clair Obscur: Expedition 33", gameID: "1903340")
    guard case .address(let url, let complete) = issue.delivery(maxLength: GameReport.maxURLLength, throughLogin: true) else {
        Issue.record("le rapport devait tenir dans l'adresse")
        return
    }
    #expect(!complete)
    #expect(IssueReport.length(of: url, throughLogin: true) <= GameReport.maxURLLength)
    #expect(IssueReport.length(of: url, throughLogin: true) > GameReport.maxURLLength * 3 / 4)
    let sent = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "rapport" }?.value)
    // le rapport et le profil y sont entiers, le debut du diagnostic aussi
    #expect(sent.hasPrefix("<!-- cidre-rapport v1 appid=1903340 -->\n```toml\n[[rapports]]\n"))
    #expect(sent.contains("[profil]\ntso = true\n") && sent.contains("ligne 1 :") && !sent.contains("ligne 400 :"))
    #expect(sent.hasSuffix("[…]\n```\n"))
}

@Test func unRapportTropLongPartParLePressePapiers() throws {
    // des notes qui, a elles seules, debordent d'une adresse : la page s'ouvre sur le formulaire
    // et le titre, sans le rapport, que Verger copie pour qu'il soit colle
    let notes = String(repeating: "Très long récit accentué, é è à ç. ", count: 120)
    let report = GameReport(date: "2026-10-13", context: .init(machine: "M4 16 Go", diagnostic: "== Cidre ==\n  ok"), verdict: .bronze, notes: notes)
    let issue = report.issue(gameName: "Jeu & Cie", gameID: "42")
    guard case .clipboard(let url) = issue.delivery(maxLength: GameReport.maxURLLength, throughLogin: true) else {
        Issue.record("le rapport ne devait pas tenir dans l'adresse")
        return
    }
    #expect(url == issue.shortURL)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.map(\.name) == ["template", "title"])
    #expect(items.last?.value == "Rapport de jeu : Jeu & Cie (42)")
    #expect(IssueReport.length(of: url, throughLogin: true) < 400)
    // ce qui est copie : le rapport entier, balise en tete, diagnostic compris
    #expect(issue.body().hasPrefix("<!-- cidre-rapport v1 appid=42 -->\n") && issue.body().contains("== Cidre =="))
    // la meme limite, mesuree sans la connexion, laisserait passer une adresse que GitHub perdrait
    let direct = issue.url(maxLength: .max)
    #expect(IssueReport.length(of: direct, throughLogin: true) > IssueReport.length(of: direct))
}

@Test func omitCeQuOnNeSaitPas() {
    // rien de connu : la date et le verdict suffisent, et le rapport reste valide
    let minimal = GameReport(date: "2026-01-02", verdict: .broken, notes: "  \n ")
    #expect(minimal.toml == "[[rapports]]\ndate = \"2026-01-02\"\netat = \"ko\"\n")
    #expect(minimal.profileToml == nil)
    #expect(minimal.text == "```toml\n[[rapports]]\ndate = \"2026-01-02\"\netat = \"ko\"\n```\n")
    // sans diagnostic : pas de journal dans l'incident, et le jeu hors Steam garde son identifiant
    let issue = minimal.issue(gameName: "Mon Jeu", gameID: "local-mon-jeu")
    #expect(issue.body() == "<!-- cidre-rapport v1 appid=local-mon-jeu -->\n" + minimal.text)
    #expect(issue.title == "Rapport de jeu : Mon Jeu (local-mon-jeu)")

    // un seul des deux fps, une machine vide
    let partial = GameReport(date: "2026-01-02", context: .init(machine: "", cidreVersion: "dev"), verdict: .bronze, fpsGame: 30)
    #expect(partial.toml == "[[rapports]]\ndate = \"2026-01-02\"\ncidre_version = \"dev\"\netat = \"bronze\"\nfps_jeu = 30\n")
    #expect(GameReport.Verdict.allCases.map(\.rawValue) == ["or", "argent", "bronze", "ko"])
}

@Test func ecritLeJourEtLesChaines() throws {
    // 2026-10-12 23:30 UTC : deja le 13 a Paris, encore le 12 en Californie.
    // Le jour est celui de la machine, pas celui d'UTC.
    let paris = try #require(TimeZone(identifier: "Europe/Paris"))
    let late = Date(timeIntervalSince1970: 1_791_847_800)
    #expect(GameReport.day(late, timeZone: paris) == "2026-10-13")
    #expect(GameReport.day(late, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2026-10-12")
    #expect(GameReport.day(late, timeZone: TimeZone(identifier: "Pacific/Auckland")!) == "2026-10-13")
    #expect(GameReport.day().count == 10)

    #expect(GameReport.quoted("") == "\"\"")
    #expect(GameReport.quoted("a\"b\\c\nd\u{01}") == "\"a\\\"b\\\\c\\nd\\u0001\"")
    #expect(GameReport.quoted("é — ok") == "\"é — ok\"")
}

@Test func coupeLeDiagnosticParLaFin() throws {
    let lines = (1...300).map { "ligne \($0) : un diagnostic un peu long, avec des accents é et des symboles + & #" }
    let issue = IssueReport(repository: "gtranche/cidre", title: "t", text: "texte", logTitle: "Diagnostic", log: lines,
                            template: "rapport-jeu.yml", field: "rapport", truncation: .head)
    let url = issue.url()
    #expect(url.absoluteString.utf8.count <= 7000)
    let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "rapport" }?.value)
    // le DEBUT est garde, la fin coupee, et la coupure est marquee
    #expect(body.contains("ligne 1 :") && !body.contains("ligne 300 :") && body.hasSuffix("[…]\n```\n"))
    // sans place du tout : le texte seul, sans marque de coupure
    #expect(issue.body(logLines: 0) == "texte")
    // le texte complet n'est pas coupe
    #expect(issue.body().contains("ligne 300 :") && !issue.body().contains("[…]"))
}

@Test func nommeLaMachineCommeLesFiches() {
    #expect(SystemInfo(macOS: "26.0", model: "Mac14,6", chip: "Apple M1 Max", memoryGB: 32).machineLabel == "M1 Max 32 Go")
    #expect(SystemInfo(macOS: "26.0", model: "Mac16,1", chip: "Apple M4", memoryGB: 16).machineLabel == "M4 16 Go")
    #expect(SystemInfo(macOS: "26.0", model: "x", chip: "", memoryGB: 16).machineLabel == nil)
    #expect(SystemInfo.current.machineLabel?.hasSuffix(" Go") == true)
}
