import Foundation

/// Un jeu est sorti en erreur : ce qu'on dit a l'utilisateur. Le lanceur de
/// Cidre ecrit, a la sortie en erreur, « cause probable : ... » puis
/// « a faire : ... » dans le journal du lancement (tests/expliquer_sortie.sh
/// cote Cidre) : c'est cela qu'on montre, pas le code de sortie. Sans ces
/// lignes (Cidre plus ancien, ou sortie avant le lanceur), le message brut de
/// la commande.
public enum LaunchFailureExplainer {
    public static func explain(log: URL, fallback: String) -> String {
        guard let text = try? String(contentsOf: log, encoding: .utf8),
              let causeRange = text.range(of: "cause probable : ", options: .backwards) else { return fallback }
        let after = text[causeRange.upperBound...]
        var cause = String(after)
        var todo: String?
        if let todoRange = after.range(of: "\n    a faire : ") {
            cause = String(after[..<todoRange.lowerBound])
            todo = String(after[todoRange.upperBound...]).components(separatedBy: "\n").first
        }
        // la cause peut continuer sur des lignes indentees (dernieres erreurs du journal)
        cause = cause.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        var parts = [L10n.format("Le jeu s'est arrêté : %@", cause)]
        if let todo = todo?.trimmingCharacters(in: .whitespaces), !todo.isEmpty {
            parts.append(L10n.format("À faire : %@", todo))
        }
        parts.append(L10n.format("Journal : %@", log.path))
        return parts.joined(separator: "\n\n")
    }
}
