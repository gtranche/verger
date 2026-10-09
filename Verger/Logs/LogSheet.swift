import CidreBridge
import SwiftUI

/// Le journal de lancement d'un jeu : ce que la commande de lancement a dit, puis
/// la fin du journal du jeu. Pour comprendre un jeu qui ne demarre pas, et pour
/// le transmettre a quelqu'un qui n'a pas la machine sous les yeux.
struct LogSheet: View {
    let game: Game
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var log = LibraryModel.LaunchLog()
    @State private var loaded = false
    @State private var errorsOnly = false
    @State private var copied = false

    private var running: Bool { library.running.contains(game.id) }

    /// Les lignes qui parlent d'un probleme.
    private static let trouble = try! Regex(
        "err:|error|erreur|fatal|exception|crash|failed|failure|echec|échec|not found|introuvable|cannot|unable|impossible|abort|assert|unhandled|denied|refus")
        .ignoresCase()

    private func shown(_ lines: [String]) -> [String] {
        errorsOnly ? lines.filter { $0.contains(Self.trouble) } : lines
    }

    /// Le texte affiche : les deux parties, chacune sous son intitule.
    private var text: String {
        var parts: [String] = []
        let command = shown(log.command), journal = shown(log.journal)
        if !command.isEmpty {
            parts.append("— " + L10n.string("Commande de lancement") + " —\n" + command.joined(separator: "\n"))
        }
        if !journal.isEmpty {
            parts.append("— " + L10n.string("Journal du jeu") + " —\n" + journal.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Journal de \(game.name)", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if running {
                    Label("En cours…", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Toggle("Erreurs seulement", isOn: $errorsOnly)
                    .toggleStyle(.checkbox)
            }

            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if log.isEmpty {
                ContentUnavailableView {
                    Label("Aucun journal", systemImage: "doc.text")
                } description: {
                    Text("Ce jeu n'a pas encore été lancé par Cidre sur ce Mac. S'il vient d'être lancé depuis Steam sans rien écrire ici, c'est que Steam ne l'a pas fait passer par Cidre.")
                }
            } else if text.isEmpty {
                ContentUnavailableView("Aucune ligne d'erreur", systemImage: "checkmark.circle",
                                       description: Text("Décoche « Erreurs seulement » pour voir tout le journal."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(verbatim: text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    // la fin du journal est ce qu'on vient chercher
                    .onAppear { proxy.scrollTo("fin", anchor: .bottom) }
                    .onChange(of: text) { proxy.scrollTo("fin", anchor: .bottom) }
                }
            }

            HStack {
                Text("Ton nom de session, tes identifiants Steam et le nom de ton Mac sont retirés de ce texte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(copied ? "Copié" : "Copier avec le diagnostic") { copy() }
                    .disabled(!loaded)
                    .help("Copie le journal affiché, précédé des versions, de l'état de l'installation et des options du jeu : de quoi le coller dans un message.")
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
        // Tant que le jeu tourne, le journal s'allonge : on le relit.
        .task(id: running) {
            repeat {
                log = await library.launchLog(of: game)
                loaded = true
                if running { try? await Task.sleep(for: .seconds(2)) }
            } while running && !Task.isCancelled
        }
    }

    private func copy() {
        Task {
            // le meme en-tete qu'un rapport d'incident, puis ce qui est affiche
            let report = await library.prepareReport(game: game, error: nil).report
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let full = IssueReport(repository: report.repository, title: report.title, text: report.text,
                                   logTitle: L10n.string("Journal"), log: lines).body()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(full, forType: .string)
            copied = true
        }
    }
}
