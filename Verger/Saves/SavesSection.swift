import CidreBridge
import SwiftUI

/// Les sauvegardes d'un jeu lance par Cidre, dans sa fiche : ou en est la copie
/// iCloud, et de quoi la mettre a jour ou la reprendre.
struct SavesSection: View {
    let game: Game
    @Environment(LibraryModel.self) private var library
    @State private var status: SaveStatus?
    @State private var loaded = false
    @State private var working = false

    private var running: Bool { library.running.contains(game.id) }

    var body: some View {
        Section {
            if let status, status.configured {
                configured(status)
            } else if loaded {
                Text("Verger ne sait pas où ce jeu range ses sauvegardes. Indique-lui le dossier pour qu'elles soient copiées sur iCloud.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choisir le dossier des sauvegardes…") { chooseFolder() }
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Sauvegardes")
        } footer: {
            if let status, status.configured {
                Text(status.onICloud
                    ? "Cidre reprend ce qui est plus récent sur iCloud au lancement du jeu, et sauvegarde quand tu le quittes. Rien n'est écrasé sans qu'une copie de l'ancienne version soit gardée."
                    : "iCloud Drive n'est pas activé sur ce Mac : la copie reste sur ce disque. Elle te protège d'une désinstallation, pas d'une panne.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // l'etat se relit a la fin d'une partie : Cidre vient de sauvegarder
        .task(id: "\(game.id)#\(running)") {
            status = await library.saveStatus(of: game)
            loaded = true
        }
    }

    @ViewBuilder
    private func configured(_ status: SaveStatus) -> some View {
        LabeledContent("État") {
            Label(Self.title(status.state), systemImage: Self.symbol(status.state))
                .foregroundStyle(Self.tint(status.state))
        }
        if let local = status.local, local.files > 0 {
            LabeledContent("Sur ce Mac") { side(local) }
        }
        if let backup = status.backup, backup.files > 0 {
            LabeledContent(status.onICloud ? "Sur iCloud" : "Copie") { side(backup) }
        }

        if working {
            HStack { ProgressView().controlSize(.small); Text("Synchronisation…") }
        } else if running {
            Text("Le jeu tourne : Cidre sauvegardera quand tu le quitteras.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            switch status.state {
            case .needsBackup, .neverBackedUp:
                syncButton("Sauvegarder maintenant", "arrow.up.circle", .backup, prominent: true)
            case .needsRestore:
                syncButton("Reprendre la version d'iCloud", "arrow.down.circle", .restore, prominent: true)
            case .diverged:
                Text("Des fichiers ont changé des deux côtés. Chaque bouton ne touche que ceux qui sont plus récents de son côté.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                syncButton("Sauvegarder maintenant", "arrow.up.circle", .backup, prominent: false)
                syncButton("Reprendre la version d'iCloud", "arrow.down.circle", .restore, prominent: false)
            case .upToDate, .empty, .unknown:
                EmptyView()
            }
        }

        Menu("Dossiers") {
            if let folder = status.folder {
                Button("Afficher les sauvegardes dans le Finder") { reveal(folder) }
            }
            if let backup = status.backupFolder, (status.backup?.files ?? 0) > 0 {
                Button("Afficher la copie dans le Finder") { reveal(backup) }
            }
            Divider()
            Button("Changer de dossier…") { chooseFolder() }
        }
        .frame(maxWidth: .infinity)
    }

    private func side(_ side: SaveStatus.Side) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: L10n.bytes(side.bytes))
            if let date = side.modified {
                Text(verbatim: "·")
                Text(date, format: .relative(presentation: .named))
            }
        }
        .foregroundStyle(.secondary)
    }

    private func syncButton(
        _ title: LocalizedStringKey, _ symbol: String, _ direction: CidreCLI.SyncDirection, prominent: Bool
    ) -> some View {
        Group {
            if prominent {
                Button { sync(direction) } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { sync(direction) } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
            }
        }
    }

    private func sync(_ direction: CidreCLI.SyncDirection) {
        working = true
        Task {
            if let updated = await library.syncSaves(of: game, direction) { status = updated }
            working = false
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Dossier des sauvegardes")
        panel.message = L10n.string("Choisis le dossier où ce jeu range ses sauvegardes : dans le dossier du jeu, ou sur le disque C: de Cidre.")
        panel.prompt = L10n.string("Choisir")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: status?.folder ?? game.path, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let updated = await library.setSavesFolder(of: game, url) { status = updated }
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private static func title(_ state: SaveStatus.State) -> String {
        switch state {
        case .upToDate: L10n.string("À jour")
        case .needsBackup: L10n.string("Modifié depuis la dernière sauvegarde")
        case .needsRestore: L10n.string("Plus récent sur iCloud")
        case .diverged: L10n.string("Modifié des deux côtés")
        case .neverBackedUp: L10n.string("Jamais sauvegardé")
        case .empty: L10n.string("Aucune sauvegarde pour l'instant")
        case .unknown: L10n.string("Inconnu")
        }
    }

    private static func symbol(_ state: SaveStatus.State) -> String {
        switch state {
        case .upToDate: "checkmark.icloud"
        case .needsBackup, .neverBackedUp: "icloud.and.arrow.up"
        case .needsRestore: "icloud.and.arrow.down"
        case .diverged: "exclamationmark.icloud"
        case .empty, .unknown: "icloud"
        }
    }

    private static func tint(_ state: SaveStatus.State) -> Color {
        switch state {
        case .upToDate: .green
        case .needsBackup, .neverBackedUp, .diverged: .orange
        case .needsRestore: .blue
        case .empty, .unknown: .secondary
        }
    }
}
