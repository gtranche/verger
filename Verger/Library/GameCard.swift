import CidreBridge
import SwiftUI

/// Une case de la grille : jaquette, nom, plateforme, et le bouton Jouer.
struct GameCard: View {
    let game: Game
    let isRunning: Bool
    let isSelected: Bool
    /// Telechargement en cours pour ce jeu, s'il y en a un.
    var download: DownloadProgress?
    /// Une version plus recente du jeu est publiee.
    var updateAvailable = false
    /// Les deux builds, pour qui se demande pourquoi le jeu est dit « pas a jour ».
    var updateHelp: String?
    /// « Jouer » met d'abord le jeu a jour.
    var updatesFirst = false
    var cancelDownload: () -> Void = {}
    /// Son deplacement vers un autre emplacement, s'il tourne.
    var move: MoveStatus?
    var stopMove: () -> Void = {}
    /// Le disque du jeu est debranche : ce qu'en dit l'infobulle (« Disque X débranché »).
    var offlineHelp: String?
    /// Forcer l'arret du jeu en cours ; `nil` quand ce n'est pas possible (jeu natif).
    var stop: (() -> Void)?
    let play: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cover(id: game.id, appid: game.appid, name: game.name)
                // hors ligne : grise, ni perdu ni desinstalle
                .saturation(game.online ? 1 : 0)
                .opacity(game.online ? 1 : 0.45)
                .overlay(alignment: .bottom) { playOverlay }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                }
                .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 10 : 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    PlatformBadge(game: game)
                    if !game.online {
                        Label("Hors ligne", systemImage: "externaldrive.badge.xmark")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.secondary)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .help(offlineHelp ?? "")
                    } else if updateAvailable {
                        Text("Mise à jour")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .help(updateHelp ?? "")
                    } else {
                        Text(L10n.bytes(game.sizeBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var playOverlay: some View {
        if let download {
            DownloadStatus(progress: download, cancel: cancelDownload)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
        } else if let move, move.isRunning {
            MoveProgress(status: move, stop: stopMove)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
        } else if isRunning {
            HStack(spacing: 8) {
                Label("En cours…", systemImage: "hourglass")
                    .font(.callout.weight(.semibold))
                if let stop {
                    Button(action: stop) {
                        Label("Forcer l'arrêt", systemImage: "stop.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Forcer l'arrêt")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
        } else if hovering && game.playable {
            Button(action: play) {
                Label("Jouer", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help(updatesFirst ? L10n.string("Une mise à jour est disponible : elle est installée, puis le jeu est lancé.") : "")
            .padding(10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// Natif (Steam macOS) ou Cidre (jeu Windows), et l'alerte si le wrapper manque.
struct PlatformBadge: View {
    let game: Game

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(tint)
                .background(tint.opacity(0.15), in: Capsule())
            if game.wrapperMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Wrapper Cidre absent dans Steam : lancer `cidre wrap`.")
            }
        }
    }

    private var label: String {
        // dossier Cidre sans installation complete : un telechargement interrompu
        if !game.installed { return L10n.string(game.source == .cidre ? "Incomplet" : "Absent") }
        if game.needsWindowsVersion { return L10n.string("Mac 32 bits") }
        return game.launch == .native ? L10n.string("Natif") : "Cidre"
    }

    private var tint: Color {
        if !game.installed { return game.source == .cidre ? .orange : .secondary }
        if game.needsWindowsVersion { return .orange }
        return game.launch == .native ? .blue : .green
    }
}
