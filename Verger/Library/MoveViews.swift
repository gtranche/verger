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

/// « Déplacer vers… » : les disques, comme sur une console -- ce Mac, puis
/// chaque disque externe branche avec sa place libre. Un disque que Cidre ne
/// connait pas encore lui est ajoute au moment de deplacer. Un deplacement se
/// confirme : il prend du temps, et le jeu ne se lance pas pendant ce temps.
struct MoveMenu: View {
    let game: Game
    /// Un petit « Déplacer… » a cote du nom du disque, dans la fiche.
    var compact = false
    @Environment(LibraryModel.self) private var library
    @State private var target: GameDisk?

    var body: some View {
        let disks = library.disks
        let here = disks.first { $0.location?.id == game.location }
        Menu(compact ? "Déplacer…" : "Déplacer vers…") {
            ForEach(disks) { disk in
                if disk.id == here?.id {
                    Text(verbatim: L10n.format("%@ (ici)", disk.name))
                } else if !disk.online {
                    Text(verbatim: disk.label)
                } else {
                    Button {
                        target = disk
                    } label: {
                        Label { Text(verbatim: disk.label) } icon: { Image(systemName: disk.symbol) }
                    }
                    .disabled(!disk.acceptsGames)
                }
            }
            if disks.count < 2 {
                Divider()
                Text("Branche un disque externe pour y mettre des jeux.")
            }
        }
        .fixedSize()
        .frame(maxWidth: compact ? nil : .infinity)
        .disabled(!game.online || game.source != .cidre || library.running.contains(game.id)
            || library.moveStatus(of: game)?.isRunning == true
            || (game.appid.map { library.downloads[$0] != nil } ?? false))
        .help("Copie le jeu sur un autre disque, vérifie la copie, puis l'efface d'ici. Sauvegardes et réglages ne bougent pas.")
        .confirmationDialog(
            Text(verbatim: L10n.format("Déplacer %@ vers « %@ » ?", game.name, target?.name ?? "")),
            isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
            presenting: target
        ) { disk in
            Button("Déplacer") { Task { await library.move(game, to: disk) } }
        } message: { disk in
            Text(verbatim: Self.explanation(game: game, to: disk))
        }
    }

    static func explanation(game: Game, to disk: GameDisk) -> String {
        var text = L10n.format("Le jeu (%@) est copié sur « %@ », la copie est vérifiée, puis il est effacé d'ici. Ses sauvegardes et ses réglages ne bougent pas. Pendant le déplacement, il ne se lance pas ; s'il est interrompu, rien n'est perdu et il pourra reprendre.", L10n.bytes(game.sizeBytes), disk.name)
        if let free = disk.freeBytes, game.sizeBytes > 0, free < game.sizeBytes {
            text += "\n\n" + L10n.format("Attention : il n'y a que %@ de libres sur « %@ ».", L10n.bytes(free), disk.name)
        }
        if disk.isNew {
            text += "\n\n" + L10n.format("Un dossier « Jeux Cidre » sera créé sur « %@ » ; le reste du disque n'est pas touché.", disk.name)
        } else if disk.location?.fileSystem == "exfat" {
            text += "\n\n" + L10n.string("Ce disque est en exFAT : les jeux s'y lancent, mais APFS convient mieux à un disque réservé au Mac.")
        }
        return text
    }
}

/// Le choix d'un dossier pour les jeux (reglages avances).
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
