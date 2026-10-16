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

            // Plusieurs emplacements (un disque externe) : ou installer.
            let usable = library.locations.filter(\.acceptsGames)
            if library.locationsSupported == true, usable.count > 1 || library.locations.contains(where: { $0.isDefault && !$0.online }) {
                HStack {
                    Picker("Installer dans", selection: Binding(
                        get: { library.effectiveInstallLocation?.id ?? "principal" },
                        set: { library.installLocation = $0 }
                    )) {
                        ForEach(usable) { location in
                            Text(verbatim: MoveMenu.label(location)).tag(location.id)
                        }
                    }
                    .fixedSize()
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                if let unplugged = library.locations.first(where: { $0.isDefault && !$0.online }) {
                    Text(verbatim: L10n.format("« %@ », l'emplacement par défaut, n'est pas branché : les jeux iront dans celui choisi ci-dessus.", unplugged.name))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }

            Divider()
            // La liste peut venir du cache d'une connexion precedente : sans
            // session, elle s'affiche mais rien ne s'installerait.
            if library.ownedState == .loaded, library.steamSession?.connected == false {
                HStack(spacing: 10) {
                    Label("Tu n'es pas connecté à Steam : cette liste date de ta dernière connexion.", systemImage: "person.badge.key")
                        .font(.callout)
                    Spacer()
                    Button("Se connecter…") { loggingIn = true }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                Divider()
            }
            content
            // apres « Reprendre » : ce qu'il est advenu des sauvegardes du jeu
            if let notice = library.importNotice {
                Divider()
                Label {
                    Text(verbatim: notice).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 560, height: 560)
        .sheet(isPresented: $loggingIn, onDismiss: { Task { await library.checkSession() } }) {
            LoginSheet().environment(library)
        }
        .task {
            if library.ownedState == .idle { await library.loadOwned() }
            await library.loadLocations()
            await library.checkSession()
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
                // Les jeux deja installes par un autre outil d'abord : au milieu
                // des centaines de jeux du compte, personne ne les trouve (4 sur
                // 1220 sur l'iMac M4, aux rangs 389 a 991).
                let inBottles = candidates.filter(\.inBottle)
                List {
                    if inBottles.isEmpty {
                        ForEach(candidates) { OwnedGameRow(game: $0) }
                    } else {
                        Section("Déjà sur ce Mac : à reprendre sans retélécharger") {
                            ForEach(inBottles) { OwnedGameRow(game: $0) }
                        }
                        Section("À télécharger") {
                            ForEach(candidates.filter { !$0.inBottle }) { OwnedGameRow(game: $0) }
                        }
                    }
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
                if game.inBottle {
                    Text(verbatim: L10n.format("Déjà installé par %@ · %@", Self.toolName(game.origin), L10n.bytes(game.sizeBytes ?? 0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if game.isMac32Bit {
                    // une version Mac existe, mais en 32 bits : inutilisable ici
                    Text(verbatim: Game.mac32BitNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(game.hasMac ? "macOS · Windows" : "Windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let progress = library.downloads[game.appid] {
                DownloadStatus(progress: progress) { library.cancelDownload(appid: game.appid) }
                    .frame(width: 190)
            } else if game.inBottle {
                // Deja installe par un autre outil : on le reprend (clone, la
                // bouteille reste intacte) plutot que de le retelecharger.
                if library.importing.contains(game.appid) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Reprendre") { library.importGame(appid: game.appid) }
                        .help(L10n.format("Déjà installé par %@ (bouteille « %@ ») : repris sans retéléchargement, la bouteille n'est pas modifiée.", Self.toolName(game.origin), game.bottle ?? ""))
                }
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
            } else if game.hasWindows {
                Button("Installer") { library.download(appid: game.appid) }
                    .help(game.isMac32Bit ? Game.mac32BitNotice : "")
            } else {
                // une version macOS 32 bits sans version Windows : rien ne la lance ici
                Text("Indisponible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

extension OwnedGameRow {
    static func toolName(_ origin: String?) -> String {
        switch origin {
        case "crossover": "CrossOver"
        case "whisky": "Whisky"
        case "heroic": "Heroic"
        default: origin ?? "?"
        }
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
                    Text("\(L10n.bytes(progress.doneBytes)) sur \(L10n.bytes(progress.totalBytes))")
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
