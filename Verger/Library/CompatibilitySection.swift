import CidreBridge
import SwiftUI

/// Ce que la base de profils de Cidre dit du jeu : l'etat sur ce Mac (l'entree
/// de sa famille de Mac quand la fiche en a une), ce qu'elle dit des autres
/// rendus sur ce Mac (le D3D12 d'un jeu regle en DXMT), et des autres Mac.
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
