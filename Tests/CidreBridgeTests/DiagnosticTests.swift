import Foundation
import Testing

@testable import CidreBridge

/// La sortie de `cidre diag 1137300 --json` (tests/diag_cidre.sh), raccourcie.
private let archiveJSON = Data("""
    {"archive":"/Users/‹utilisateur›/Library/Application Support/Cidre/diagnostics/diag-1137300-20261017-130513.tar.gz",\
    "dossier":"/Users/‹utilisateur›/Library/Application Support/Cidre/diagnostics/diag-1137300-20261017-130513",\
    "octets":10883,"format":"tar.gz","jeu":{"id":"1137300","nom":"Sherlock Holmes Chapter One"},\
    "resume":["diagnostic Cidre du 2026-10-17 13:05 -- jeu 1137300 (Sherlock Holmes Chapter One)",\
    "cause probable : le client Steam est ferme"],\
    "fichiers":[{"nom":"doctor.txt","octets":35},{"nom":"plantages/wine-2026-10-15-235013.ips","octets":15576}],\
    "masques":{"jeton":4,"chemin":12,"ip":0},"capture":false,"service":{"configure":true,"chiffre":true,"url":"https://x"}}
    """.utf8)

@Test func litLArchiveDeDiagnostic() throws {
    let a = try JSONDecoder().decode(DiagnosticArchive.self, from: archiveJSON)
    #expect(a.game.id == "1137300")
    #expect(a.game.name == "Sherlock Holmes Chapter One")
    #expect(a.bytes == 10883)
    #expect(a.files.map(\.name) == ["doctor.txt", "plantages/wine-2026-10-15-235013.ips"])
    #expect(a.summary.count == 2)
    #expect(a.service.configured && a.service.encrypted)
    #expect(!a.screenshot)
    #expect(a.archiveURL.lastPathComponent == "diag-1137300-20261017-130513.tar.gz")
}

@Test func ditCeQuiAEteMasqueDansUnOrdreFixe() throws {
    L10n.language = "fr"
    let a = try JSONDecoder().decode(DiagnosticArchive.self, from: archiveJSON)
    // les chemins avant les jetons, les categories a zero absentes
    #expect(a.maskedDescription == ["12 noms ou chemins personnels", "4 jetons ou identifiants"])
}

@Test func litLeCodeRenduParLEnvoi() throws {
    let r = try JSONDecoder().decode(DiagnosticReceipt.self, from: Data(#"{"code":"CIDRE-7K3P-Q9","expire":"2026-11-16","chiffre":true,"octets":11200}"#.utf8))
    #expect(r.code == "CIDRE-7K3P-Q9")
    #expect(r.expires == "2026-11-16")
    #expect(r.encrypted)
}

@Test func classeLesEchecsDEnvoi() {
    let json = { (e: String) in Data(#"{"erreur":"\#(e)","message":"m"}"#.utf8) }
    #expect(DiagnosticSendError.from(status: 3, output: json("non_configure"), stderr: Data()) == .notConfigured("m"))
    #expect(DiagnosticSendError.from(status: 4, output: json("reseau"), stderr: Data()) == .network("m"))
    #expect(DiagnosticSendError.from(status: 5, output: json("refuse"), stderr: Data()) == .refused("m"))
    #expect(DiagnosticSendError.from(status: 6, output: json("archive"), stderr: Data()) == .failed("m"))
    // un Cidre qui n'ecrit pas de JSON : le code de sortie suffit
    #expect(DiagnosticSendError.from(status: 4, output: Data(), stderr: Data("pas de reseau".utf8)) == .network("pas de reseau"))
}

@Test func repliSurLeFormulaireRapportDeJeu() throws {
    L10n.language = "fr"
    let a = try JSONDecoder().decode(DiagnosticArchive.self, from: archiveJSON)
    let context = GameReport.Context(machine: "M1 Max 32 Go", model: "MacBookPro18,2", macOS: "26.5.2", cidreVersion: "1.5.13", gpuFamily: 7)
    let issue = a.fallbackIssue(context: context)
    #expect(issue.repository == "gtranche/cidre")
    #expect(issue.template == GameReport.issueTemplate)
    #expect(issue.field == GameReport.issueField)
    #expect(issue.title == "Rapport de jeu : Sherlock Holmes Chapter One (1137300)")
    let body = issue.body()
    #expect(body.contains(#"etat = "ko""#))
    // ce qu'a ajoute 661cd58 : modele du Mac et version de macOS
    #expect(body.contains(#"modele = "MacBookPro18,2""#))
    #expect(body.contains(#"macos_version = "26.5.2""#))
    #expect(body.contains("diag-1137300-20261017-130513.tar.gz"))
    #expect(body.contains("cause probable : le client Steam est ferme"))
    #expect(issue.url().absoluteString.contains("template=rapport-jeu.yml"))
}
