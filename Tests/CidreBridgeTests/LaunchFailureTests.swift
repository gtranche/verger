import Foundation
import Testing

@testable import CidreBridge

/// Le message montre a l'utilisateur quand un jeu sort en erreur : ce que le
/// lanceur de Cidre a ecrit dans le journal du lancement (« cause probable »,
/// « a faire »), pas le code de sortie. Reproduit ici la logique de
/// LaunchFailureExplainer sur des journaux fabriques.
struct LaunchFailureTests {
    private func journal(_ contenu: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("play-test-\(UUID().uuidString).log")
        try contenu.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func causeEtAFaire() throws {
        let log = try journal("""
        lancement Cidre : x.exe
            le jeu s'est termine sur le code 53
            cause probable : le client Steam de macOS ne tournait pas : un jeu protege par Steam se ferme aussitot sans lui
            a faire : ouvrir Steam et s'y connecter, puis relancer
        """)
        let texte = LaunchFailureExplainer.explain(log: log, fallback: "brut")
        #expect(texte.contains("le client Steam de macOS ne tournait pas"))
        #expect(texte.contains("ouvrir Steam et s'y connecter"))
        #expect(texte.contains(log.path))
        #expect(!texte.contains("brut"))
    }

    @Test func causeSurPlusieursLignes() throws {
        let log = try journal("""
            le jeu s'est termine sur le code 7
            cause probable : le jeu s'est termine sur le code 7 sans signature connue ; dernieres erreurs du journal :
                err:ole:CoCreateInstance no class object
                err:winediag:truc une erreur parlante
            a faire : `cidre doctor` pour l'etat de l'installation
        """)
        let texte = LaunchFailureExplainer.explain(log: log, fallback: "brut")
        #expect(texte.contains("une erreur parlante"))
        #expect(texte.contains("cidre doctor"))
    }

    @Test func sansExplicationLeMessageBrut() throws {
        let log = try journal("lancement Cidre : x.exe\n    le jeu s'est termine sur le code 1\n")
        #expect(LaunchFailureExplainer.explain(log: log, fallback: "brut") == "brut")
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("nexiste-pas.log")
        #expect(LaunchFailureExplainer.explain(log: absent, fallback: "brut") == "brut")
    }
}
