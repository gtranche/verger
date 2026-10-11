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

    // l'incident : titre fixe, label, le diagnostic en journal
    let issue = report.issue(gameName: "Dead Cells", gameID: "588650")
    #expect(issue.repository == "gtranche/cidre")
    #expect(issue.title == "Rapport de jeu : Dead Cells (588650)")
    #expect(issue.labels == ["rapport-jeu"])
    let body = issue.body()
    #expect(body.hasPrefix("```toml\n[[rapports]]\n"))
    #expect(body.contains("```\n\n**Profil effectif**\n```toml\n[profil]\n"))
    #expect(body.contains("```text\n== Verger ==\n  version : 0.3.10\n== Cidre ==\n  ok\n```"))
    let items = try #require(URLComponents(url: issue.url(), resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.first { $0.name == "labels" }?.value == "rapport-jeu")
    #expect(items.first { $0.name == "title" }?.value == "Rapport de jeu : Dead Cells (588650)")
    #expect(items.first { $0.name == "body" }?.value == body)
}

@Test func omitCeQuOnNeSaitPas() {
    // rien de connu : la date et le verdict suffisent, et le rapport reste valide
    let minimal = GameReport(date: "2026-01-02", verdict: .broken, notes: "  \n ")
    #expect(minimal.toml == "[[rapports]]\ndate = \"2026-01-02\"\netat = \"ko\"\n")
    #expect(minimal.profileToml == nil)
    #expect(minimal.text == "```toml\n[[rapports]]\ndate = \"2026-01-02\"\netat = \"ko\"\n```\n")
    // sans diagnostic : pas de journal dans l'incident, et le jeu hors Steam garde son identifiant
    let issue = minimal.issue(gameName: "Mon Jeu", gameID: "local-mon-jeu")
    #expect(issue.body() == minimal.text)
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
                            labels: ["rapport-jeu"], truncation: .head)
    let url = issue.url()
    #expect(url.absoluteString.utf8.count <= 7000)
    let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value)
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
