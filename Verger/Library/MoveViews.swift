import CidreBridge
import SwiftUI

/// Barre d'avancement d'un deplacement de jeu, avec son bouton d'arret.
struct MoveProgress: View {
    let status: MoveStatus
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if status.phase == .copie, let progress = status.progress, progress.totalBytes > 0 {
                    ProgressView(value: progress.fraction)
                    Text("Déplacement : \(L10n.bytes(progress.doneBytes)) sur \(L10n.bytes(progress.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                    Text(verbatim: status.phaseLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: stop) {
                Label("Arrêter le déplacement", systemImage: "xmark.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Arrêter le déplacement : le jeu reste où il était, et la copie pourra reprendre où elle en était.")
        }
    }
}

/// « Déplacer vers… » : les autres emplacements branches, ou en ajouter un.
/// Un deplacement se confirme : il prend du temps, et le jeu ne se lance pas
/// pendant ce temps.
struct MoveMenu: View {
    let game: Game
    @Environment(LibraryModel.self) private var library
    @State private var target: StorageLocation?

    private var targets: [StorageLocation] {
        library.locations.filter { $0.id != game.location && $0.acceptsGames }
    }

    var body: some View {
        Menu("Déplacer vers…") {
            ForEach(targets) { location in
                Button {
                    target = location
                } label: {
                    Text(verbatim: Self.label(location))
                }
            }
            let offline = library.locations.filter { $0.id != game.location && !$0.online }
            if !offline.isEmpty {
                Section("Débranchés") {
                    ForEach(offline) { location in
                        Text(verbatim: location.name)
                    }
                }
            }
            if !targets.isEmpty || !offline.isEmpty { Divider() }
            Button("Ajouter un disque ou un dossier…") {
                Task {
                    guard let folder = StoragePanel.chooseFolder() else { return }
                    if let added = await library.addLocation(folder), added.acceptsGames, added.id != game.location {
                        target = added
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(!game.online || game.source != .cidre || library.running.contains(game.id)
            || library.moveStatus(of: game)?.isRunning == true
            || (game.appid.map { library.downloads[$0] != nil } ?? false))
        .help("Copie le jeu sur un autre disque, vérifie la copie, puis l'efface d'ici. Sauvegardes et réglages ne bougent pas.")
        .confirmationDialog(
            Text(verbatim: L10n.format("Déplacer %@ vers « %@ » ?", game.name, target?.name ?? "")),
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
            presenting: target
        ) { location in
            Button("Déplacer") { library.move(game, to: location) }
        } message: { location in
            Text(verbatim: Self.explanation(game: game, to: location))
        }
    }

    static func label(_ location: StorageLocation) -> String {
        guard let free = location.freeBytes else { return location.name }
        return L10n.format("%@ — %@ libres", location.name, L10n.bytes(free))
    }

    static func explanation(game: Game, to location: StorageLocation) -> String {
        var text = L10n.format("Le jeu (%@) est copié sur « %@ », la copie est vérifiée, puis il est effacé d'ici. Ses sauvegardes et ses réglages ne bougent pas. Pendant le déplacement, il ne se lance pas ; s'il est interrompu, rien n'est perdu et il pourra reprendre.", L10n.bytes(game.sizeBytes), location.name)
        if let free = location.freeBytes, game.sizeBytes > 0, free < game.sizeBytes {
            text += "\n\n" + L10n.format("Attention : il n'y a que %@ de libres sur « %@ ».", L10n.bytes(free), location.name)
        }
        if location.fileSystem == "exfat" {
            text += "\n\n" + L10n.string("Ce disque est en exFAT : les jeux s'y lancent, mais APFS convient mieux à un disque réservé au Mac.")
        }
        return text
    }
}

/// Le choix d'un disque ou d'un dossier pour les jeux.
enum StoragePanel {
    @MainActor
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Ajouter un emplacement pour les jeux")
        panel.message = L10n.string("Choisis un disque (un dossier « Jeux Cidre » y sera créé) ou un dossier.")
        panel.prompt = L10n.string("Ajouter")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
