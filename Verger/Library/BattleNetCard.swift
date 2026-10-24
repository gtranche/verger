import CidreBridge
import SwiftUI

/// La tuile du client Battle.net, toujours en tete de la bibliotheque : un jeu
/// Blizzard ne tourne pas sans le client connecte, c'est donc lui qu'on lance.
/// Pas installe : la tuile l'installe (l'installeur officiel, que l'on suit
/// dans sa fenetre). Installe : elle l'ouvre ; on lance ses jeux depuis lui.
struct BattleNetCard: View {
    let status: BattleNetStatus
    /// La derniere etape de l'installation en cours ; `installing` sans etape : elle demarre.
    var step: BattleNetEvent?
    var installing = false
    /// Le client vient d'etre ouvert et ne s'est pas encore montre.
    var opening = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        // occupee (installation, ouverture) : la tuile reste vive, le clic ne fait rien
        Button { if !installing && !opening { action() } } label: {
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .overlay(alignment: .bottom) { overlay }
                    .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 10 : 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Battle.net")
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(tint)
                            .background(tint.opacity(0.15), in: Capsule())
                        if status.installed, status.gameCount > 0 {
                            Text(status.gameCount == 1
                                 ? L10n.string("1 jeu")
                                 : L10n.format("%@ jeux", String(status.gameCount)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
        .accessibilityLabel("Battle.net")
    }

    /// Un carton aux couleurs du client, sans son logo.
    private var artwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.0, green: 0.45, blue: 0.95), Color(red: 0.02, green: 0.09, blue: 0.24)],
                startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 44))
                Text(verbatim: "Battle.net")
                    .font(.title2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .saturation(status.installed || installing ? 1 : 0.35)
    }

    @ViewBuilder
    private var overlay: some View {
        if installing {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView().controlSize(.small)
                Text(step?.stepLabel ?? L10n.string("Installation de Battle.net…"))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(8)
        } else if status.open {
            Label(status.runningGame.map { L10n.format("En jeu : %@", $0) } ?? L10n.string("Ouvert"),
                  systemImage: status.runningGame == nil ? "checkmark.circle.fill" : "gamecontroller.fill")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        } else if opening {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Ouverture…").font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
        } else if !status.installed || hovering {
            // le bouton se dessine seulement : toute la tuile fait l'action
            Label(status.installed ? "Ouvrir" : "Installer",
                  systemImage: status.installed ? "arrow.up.forward.app" : "arrow.down.circle")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: Capsule())
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var badge: String {
        if installing { return L10n.string("Installation") }
        if !status.installed { return L10n.string("Pas installé") }
        return status.open ? L10n.string("Ouvert") : L10n.string("Installé")
    }

    private var tint: Color {
        if installing { return .orange }
        if !status.installed { return .secondary }
        return status.open ? .green : .blue
    }

    private var help: String {
        if !status.installed {
            return L10n.string("Installe le client Battle.net : son installeur s'ouvre, suis-le, puis connecte-toi dans le client.")
        }
        return L10n.string("Ouvre le client Battle.net : connecte-toi, puis lance, installe ou mets à jour tes jeux depuis lui.")
    }
}
