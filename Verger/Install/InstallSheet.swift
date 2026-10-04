import CidreBridge
import SwiftUI

/// « Installer un jeu Steam » : les jeux que possede le compte et qui ne sont
/// pas encore installes. La version Windows se telecharge dans le dossier Cidre
/// (`cidre dl`) ; la version macOS, quand elle existe, s'installe par Steam.
struct InstallSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var loggingIn = false

    private var candidates: [OwnedGame] {
        library.owned.filter { game in
            (!game.installed || library.downloads[game.appid] != nil)
                && (search.isEmpty || game.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Installer un jeu Steam").font(.headline)
                Spacer()
                Button {
                    Task { await library.loadOwned(refresh: true) }
                } label: {
                    Label("Actualiser depuis Steam", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Redemander à Steam la liste des jeux du compte")
                .disabled(library.ownedState == .loading)
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            TextField("Rechercher dans tes jeux Steam", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 10)

            Divider()
            content
        }
        .frame(width: 560, height: 560)
        .task {
            if library.ownedState == .idle { await library.loadOwned() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.ownedState {
        case .idle, .loading:
            ProgressView("Lecture de tes jeux Steam…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sessionMissing:
            ContentUnavailableView {
                Label("Connexion Steam requise", systemImage: "person.badge.key")
            } description: {
                Text("Connecte-toi une fois pour que Verger puisse lire ta bibliothèque et télécharger tes jeux. Ensuite la session est mémorisée.")
            } actions: {
                Button("Se connecter à Steam…") { loggingIn = true }
                    .buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $loggingIn) { LoginSheet().environment(library) }
        case let .failed(message):
            ContentUnavailableView {
                Label("Liste indisponible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await library.loadOwned(refresh: true) } }
            }
        case .loaded:
            if candidates.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "Tout est déjà installé" : "Aucun jeu ne correspond",
                    systemImage: "leaf")
            } else {
                List(candidates) { game in
                    OwnedGameRow(game: game)
                }
                .listStyle(.inset)
                Divider()
                Text("\(candidates.count) jeux")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }
}

private struct OwnedGameRow: View {
    let game: OwnedGame
    @Environment(LibraryModel.self) private var library

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name).lineLimit(1)
                Text(game.hasMac ? "macOS · Windows" : "Windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let progress = library.downloads[game.appid] {
                DownloadStatus(progress: progress) { library.cancelDownload(appid: game.appid) }
                    .frame(width: 190)
            } else if game.hasMac {
                // La version macOS est native : c'est le choix par defaut. La
                // version Windows par Cidre reste possible.
                Menu("Installer") {
                    Button("Version macOS (par Steam)") { library.installNative(appid: game.appid) }
                    if game.hasWindows {
                        Button("Version Windows (par Cidre)") { library.download(appid: game.appid) }
                    }
                }
                .fixedSize()
            } else {
                Button("Installer") { library.download(appid: game.appid) }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Barre d'avancement d'un telechargement, avec son bouton d'arret.
struct DownloadStatus: View {
    let progress: DownloadProgress
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if progress.totalBytes > 0 {
                    ProgressView(value: progress.fraction)
                    Text("\(progress.doneBytes.formatted(.byteCount(style: .file))) sur \(progress.totalBytes.formatted(.byteCount(style: .file)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                    Text("Connexion à Steam…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: cancel) {
                Label("Arrêter le téléchargement", systemImage: "xmark.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Arrêter le téléchargement (il reprendra où il en était)")
        }
    }
}
