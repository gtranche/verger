import Foundation

/// La langue de l'interface, pour les textes fabriques hors de SwiftUI (messages
/// d'erreur, titres de panneaux). Les textes sont ecrits en francais dans le
/// code ; `en.lproj/Localizable.strings` porte leur traduction anglaise.
/// Les vues SwiftUI, elles, suivent `\.locale` : meme table, meme langue.
public enum L10n {
    /// `nil` : la langue du systeme.
    nonisolated(unsafe) public static var language: String? {
        didSet { table = load() }
    }

    nonisolated(unsafe) private static var table: Bundle? = load()

    /// La langue effective : le choix de l'utilisateur, sinon le francais si le
    /// systeme est en francais, l'anglais partout ailleurs.
    public static var effectiveLanguage: String {
        if let language, ["fr", "en"].contains(language) { return language }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("fr") ? "fr" : "en"
    }

    public static var locale: Locale { Locale(identifier: effectiveLanguage == "fr" ? "fr_FR" : "en_US") }

    private static func load() -> Bundle? {
        // en francais, la cle est le texte : pas de table a charger
        guard effectiveLanguage != "fr",
              let path = Bundle.main.path(forResource: effectiveLanguage, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// Le texte dans la langue de l'interface ; le texte francais lui-meme si
    /// la traduction manque.
    public static func string(_ french: String) -> String {
        table?.localizedString(forKey: french, value: french, table: nil) ?? french
    }

    /// Comme `string`, pour un texte a trous (`%@`, `%lld`).
    public static func format(_ french: String, _ arguments: CVarArg...) -> String {
        String(format: string(french), locale: locale, arguments: arguments)
    }

    /// Une taille de fichier, ecrite dans la langue de l'interface.
    public static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file).locale(locale))
    }
}
