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
    var cancelDownload: () -> Void = {}
    let play: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cover(appid: game.appid, name: game.name)
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
                    if updateAvailable {
                        Text("Mise à jour")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    } else {
                        Text(game.sizeBytes.formatted(.byteCount(style: .file)))
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
        } else if isRunning {
            Label("En cours…", systemImage: "hourglass")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        } else if hovering && game.installed {
            Button(action: play) {
                Label("Jouer", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
        if !game.installed { return game.source == .cidre ? "Incomplet" : "Absent" }
        return game.launch == .native ? "Natif" : "Cidre"
    }

    private var tint: Color {
        if !game.installed { return game.source == .cidre ? .orange : .secondary }
        return game.launch == .native ? .blue : .green
    }
}
