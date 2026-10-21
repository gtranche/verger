import CidreBridge
import SwiftUI

/// Ce que la base de profils de Cidre dit du jeu : l'etat sur ce Mac (l'entree
/// de sa famille de Mac quand la fiche en a une), ce qu'elle dit des autres
/// rendus sur ce Mac (le D3D12 d'un jeu regle en DXMT), et des autres Mac ;
/// puis le resume ProtonDB que la fiche reprend (joueurs sous Linux), et si
/// la fiche n'est que provisoire.
struct CompatibilitySection: View {
    let compatibility: GameCompatibility

    var body: some View {
        Section("Compatibilité") {
            if let here = compatibility.here {
                LabeledContent("Sur ce Mac") { VerdictBadge(verdict: here.verdict) }
                details(here)
            } else {
                LabeledContent("Sur ce Mac") { VerdictBadge(verdict: .untested) }
            }
            ForEach(Array(compatibility.otherRoutesHere.enumerated()), id: \.offset) { _, other in
                LabeledContent {
                    VerdictBadge(verdict: other.verdict)
                } label: {
                    Text(verbatim: L10n.format("Autre rendu : %@", other.route?.title ?? L10n.string("autre voie")))
                    if let options = other.options, other.verdict != .broken {
                        Text("Options : \(options)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let notes = other.notes {
                        Text(verbatim: notes).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !compatibility.elsewhere.isEmpty {
                DisclosureGroup("Sur les autres Mac") {
                    ForEach(Array(compatibility.elsewhere.enumerated()), id: \.offset) { _, other in
                        LabeledContent {
                            VerdictBadge(verdict: other.verdict)
                        } label: {
                            Text(verbatim: [other.name, other.route?.title].compactMap { $0 }.joined(separator: " · "))
                            if let notes = other.notes {
                                Text(verbatim: notes).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if let protonDB = compatibility.protonDB {
                LabeledContent {
                    ProtonDBBadge(tier: protonDB.tier)
                } label: {
                    Text("ProtonDB (Linux)")
                    if let reports = protonDB.reports {
                        Text(verbatim: L10n.format("%lld rapports de joueurs sous Linux, pas sur Mac", reports))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let url = protonDB.url {
                    Link("Voir sur ProtonDB", destination: url)
                }
            }
            if let external = compatibility.external {
                ExternalSourcesView(external: external)
            }
            if compatibility.provisional {
                Text("Fiche provisoire : Cidre ne connaît pas encore ce jeu, seul le résumé de ProtonDB est repris. La vraie fiche la remplacera dès qu'elle existera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// La voie, les mesures et leur machine, les notes.
    @ViewBuilder
    private func details(_ status: GameCompatibility.Status) -> some View {
        if let route = status.route {
            LabeledContent("Rendu", value: route.title)
        }
        if let scope = status.scope {
            LabeledContent("Pour", value: scope)
        }
        let fps = [status.fpsMenu.map { L10n.format("menu %lld i/s", $0) }, status.fpsGame.map { L10n.format("jeu %lld i/s", $0) }]
            .compactMap { $0 }
        if !fps.isEmpty || status.machine != nil {
            LabeledContent("Mesuré") {
                Text(verbatim: (fps + [status.machine.map { L10n.format("sur %@", $0) }].compactMap { $0 }).joined(separator: " · "))
            }
        }
        if let notes = status.notes {
            Text(verbatim: notes)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Ce que les bases publiques disent du jeu (import de Cidre) : l'anti-triche
/// en clair (il decide souvent de tout), le reste replie. Pour information :
/// rien de tout cela n'est applique au lancement.
struct ExternalSourcesView: View {
    let external: ExternalSources

    var body: some View {
        if let antiCheat = external.antiCheat {
            LabeledContent {
                Text(verbatim: antiCheat.name)
            } label: {
                Text("Anti-triche")
                if antiCheat.blocksOnline {
                    Text("Son mode en ligne ne démarre pas sous Wine sur Mac : le jeu ne marche souvent qu'hors ligne, s'il le permet.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                sourceLine(antiCheat.source)
            }
        }
        DisclosureGroup("Ce qu'en disent d'autres sources") {
            fact("Moteur", external.engine)
            fact("Graphismes", external.apis)
            fact("Exécutable", external.bits)
            fact("DRM", external.drm)
            if let agw = external.appleGamingWiki {
                ForEach(agw.verdicts, id: \.route) { entry in
                    LabeledContent {
                        Text(verbatim: entry.verdict.title)
                    } label: {
                        Text(verbatim: L10n.format("AppleGamingWiki : %@", entry.route.title))
                    }
                }
                if let last = agw.lastReport {
                    Text(verbatim: L10n.format("Dernier témoignage sur AppleGamingWiki : %@", last))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let url = agw.url { Link("Voir sur AppleGamingWiki", destination: url) }
            }
            if let co = external.crossOver {
                LabeledContent("Recette CrossOver") {
                    Text(verbatim: [co.graphics.map(Self.graphicsTitle), co.bottle, co.version.map { "CrossOver \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                if let overrides = co.dllOverrides {
                    LabeledContent("DLL forcées par CrossOver", value: overrides)
                }
                if let deps = co.dependencies {
                    LabeledContent("Dépendances (CrossOver)", value: deps)
                }
                if let url = co.url { Link("Voir chez CodeWeavers", destination: url) }
            }
            if let pcgw = external.pcGamingWiki {
                ForEach(pcgw.settingsFiles, id: \.self) { path in
                    LabeledContent("Réglages du jeu") { Text(verbatim: path).textSelection(.enabled) }
                }
                ForEach(pcgw.saves, id: \.self) { path in
                    LabeledContent("Sauvegardes") { Text(verbatim: path).textSelection(.enabled) }
                }
                if let url = pcgw.url { Link("Voir sur PCGamingWiki", destination: url) }
            }
            Text("Repris de ProtonDB, PCGamingWiki, AppleGamingWiki et CrossOver, pour information : Cidre ne règle rien d'après ces sources tant qu'un essai ne l'a pas confirmé.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func fact(_ title: LocalizedStringKey, _ fact: ExternalSources.Fact?) -> some View {
        if let fact {
            LabeledContent {
                Text(verbatim: fact.value)
            } label: {
                Text(title)
                sourceLine(fact.source)
            }
        }
    }

    /// « pcgamingwiki 2026-10-15 » -> « d'après PCGamingWiki (2026-10-15) » ;
    /// rien sans source (valeur ecrite ou verifiee a la main).
    @ViewBuilder
    private func sourceLine(_ source: String?) -> some View {
        if let source, let line = Self.sourceTitle(source) {
            Text(verbatim: line).font(.caption).foregroundStyle(.secondary)
        }
    }

    static func sourceTitle(_ source: String) -> String? {
        let parts = source.split(separator: " ", maxSplits: 1).map(String.init)
        guard let id = parts.first else { return nil }
        let name = switch id {
        case "pcgamingwiki": "PCGamingWiki"
        case "applegamingwiki": "AppleGamingWiki"
        case "protondb": "ProtonDB"
        case "crossover": "CrossOver"
        case "steam": "Steam"
        case "cidre-test": "Cidre"
        default: id
        }
        return parts.count > 1 ? L10n.format("d'après %@ (%@)", name, parts[1]) : L10n.format("d'après %@", name)
    }

    static func graphicsTitle(_ id: String) -> String {
        switch id {
        case "d3dmetal": "D3DMetal"
        case "dxvk": "DXVK"
        case "dxmt": "DXMT"
        default: id
        }
    }
}

/// L'etat d'une fiche, en pastille : or, argent, bronze, ne marche pas.
struct VerdictBadge: View {
    let verdict: GameCompatibility.Verdict

    var body: some View {
        Text(verbatim: verdict.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
            .help(verdict.explanation)
    }

    private var tint: Color {
        switch verdict {
        case .gold: .yellow
        case .silver: .gray
        case .bronze: .brown
        case .broken: .red
        case .untested: .secondary
        }
    }
}

/// Le palier ProtonDB, en pastille, aux couleurs de ProtonDB.
struct ProtonDBBadge: View {
    let tier: GameCompatibility.ProtonDBTier

    var body: some View {
        Text(verbatim: tier.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
            .help(L10n.string("Le palier de ProtonDB : comment le jeu tourne sous Linux avec Proton. Un indice pour Cidre, pas une mesure sur Mac."))
    }

    private var tint: Color {
        switch tier {
        case .platinum: .teal
        case .gold: .yellow
        case .silver: .gray
        case .bronze: .brown
        case .borked: .red
        case .pending: .secondary
        }
    }
}
