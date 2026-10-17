import CidreBridge
import SwiftUI

/// « Envoyer un diagnostic » : Cidre fait l'archive (masquee) du jeu, Verger
/// montre ce qui partirait, et n'envoie qu'apres « Envoyer ». En retour, un code
/// court (CIDRE-7K3P-Q9) a donner a la personne qui aide. Sans service (pas de
/// reseau, Cidre sans adresse de depot) : l'archive dans le Finder et le
/// formulaire GitHub prerempli.
struct DiagnosticSendSheet: View {
    let game: Game
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        /// avant de faire l'archive : la capture se demande ici
        case ask
        case preparing
        case review(DiagnosticArchive)
        case sending(DiagnosticArchive)
        case sent(DiagnosticReceipt)
        /// envoi impossible : `archive` reste sur le Mac (nil : pas d'archive du tout)
        case fallback(DiagnosticArchive?, String)
    }

    @State private var step: Step = .ask
    @State private var screenshot = false
    @State private var copied = false
    @State private var openedGitHub = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Envoyer un diagnostic", systemImage: "paperplane")
                .font(.headline)
            content
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .ask: askView
        case .preparing:
            ProgressView("Préparation du diagnostic… Cela peut durer une ou deux minutes.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer { EmptyView() }
        case .review(let archive): reviewView(archive, sending: false)
        case .sending(let archive): reviewView(archive, sending: true)
        case .sent(let receipt): sentView(receipt)
        case .fallback(let archive, let reason): fallbackView(archive, reason: reason)
        }
    }

    // MARK: Avant l'archive

    private var askView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cidre rassemble ce qui aide à comprendre un problème avec \(game.name) : versions, état de l'installation, dernier journal du jeu, réglages, rapports de plantage, état des shaders et du système. Rien ne part avant que tu aies vu le contenu et appuyé sur « Envoyer ».")
                .fixedSize(horizontal: false, vertical: true)
            Label("Ton nom, ton dossier personnel, le nom de ton Mac, tes comptes Steam, les jetons, les adresses e-mail et IP sont masqués.", systemImage: "eye.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $screenshot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Joindre une capture d'écran")
                    Text("Verger se cache trois secondes, le temps de photographier l'écran entier : mets le jeu en avant. Une image n'est pas masquée.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            footer {
                Button("Préparer le diagnostic") { prepare() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Ce qui partirait

    private func reviewView(_ archive: DiagnosticArchive, sending: Bool) -> some View {
        let size = ByteCountFormatter.string(fromByteCount: Int64(archive.bytes), countStyle: .file)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Voici ce qui partirait, \(size) au total. Relis le résumé ; « Afficher les fichiers » montre tout le contenu.")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: archive.summary.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    Text("Fichiers").font(.caption.bold())
                    ForEach(archive.files) { file in
                        HStack {
                            Text(verbatim: file.name)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.monospaced())
                    }
                }
                .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            let masked = archive.maskedDescription
            Label(masked.isEmpty ? L10n.string("Rien d'identifiant n'a été trouvé à masquer.")
                                 : L10n.format("Masqué : %@.", masked.joined(separator: ", ")),
                  systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if archive.screenshot {
                Label("La capture d'écran part telle quelle : vérifie qu'elle ne montre rien de privé.", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if archive.service.configured {
                Label(archive.service.encrypted
                      ? L10n.string("Le diagnostic est chiffré avant de partir : seule l'équipe de Cidre peut le lire. Il est effacé au bout de 30 jours.")
                      : L10n.string("Le diagnostic part sans chiffrement vers le service de Cidre. Il est effacé au bout de 30 jours."),
                      systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer {
                Button("Afficher les fichiers") { NSWorkspace.shared.activateFileViewerSelecting([archive.folderURL]) }
                if archive.service.configured {
                    Button(sending ? "Envoi…" : "Envoyer") { send(archive) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(sending)
                } else {
                    Button("Continuer sans envoi") {
                        step = .fallback(archive, L10n.string("Ce Cidre n'a pas de service de diagnostic configuré."))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: Le code

    private func sentView(_ receipt: DiagnosticReceipt) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Diagnostic envoyé. Donne ce code à la personne qui t'aide :")
                .multilineTextAlignment(.center)
            Text(verbatim: receipt.code)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            Button(copied ? "Copié" : "Copier le code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(receipt.code, forType: .string)
                copied = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Il donne accès à ce seul diagnostic, et seulement à l'équipe de Cidre. Effacé le \(receipt.expires).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Le repli

    private func fallbackView(_ archive: DiagnosticArchive?, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(reason, systemImage: "wifi.exclamationmark")
                .fixedSize(horizontal: false, vertical: true)
            if let archive {
                Text("Le diagnostic est prêt sur ton Mac. Pour le transmettre : ouvre le formulaire GitHub (déjà rempli), puis glisse l'archive dans l'incident. Il faut un compte GitHub, et l'incident sera public : l'archive est masquée, relis-la quand même.")
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: archive.archiveURL.lastPathComponent)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if openedGitHub {
                    Label("GitHub est ouvert. Glisse l'archive dans le champ de texte de l'incident.", systemImage: "arrow.down.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Aucune archive n'a pu être faite. « Signaler un problème » prépare un incident avec la fin du journal.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            footer {
                if let archive {
                    Button("Afficher l'archive dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([archive.archiveURL])
                    }
                    Button("Ouvrir le formulaire GitHub") { openGitHub(archive) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    if archive.service.configured {
                        Button("Réessayer l'envoi") { send(archive) }
                    }
                }
            }
        }
    }

    private func footer<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        HStack {
            Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            buttons()
        }
    }

    // MARK: Actions

    private func prepare() {
        step = .preparing
        let withScreenshot = screenshot
        Task {
            if withScreenshot {
                // la capture est prise trois secondes apres l'appel : le jeu, pas Verger
                NSApp.hide(nil)
                Task { try? await Task.sleep(for: .seconds(5)); NSApp.unhide(nil) }
            }
            do {
                step = .review(try await library.makeDiagnostic(for: game, screenshot: withScreenshot))
            } catch {
                step = .fallback(nil, L10n.format("Le diagnostic n'a pas pu être fait : %@", error.localizedDescription))
            }
        }
    }

    private func send(_ archive: DiagnosticArchive) {
        step = .sending(archive)
        Task {
            do {
                step = .sent(try await library.sendDiagnostic(archive))
            } catch let error as DiagnosticSendError {
                let reason: String
                switch error {
                case .notConfigured: reason = L10n.string("Ce Cidre n'a pas de service de diagnostic configuré.")
                case .network: reason = L10n.string("Le service de diagnostic ne répond pas (pas de réseau ?).")
                case .refused(let m): reason = L10n.format("Le service de diagnostic a refusé l'envoi : %@", m)
                case .failed(let m): reason = L10n.format("L'envoi a échoué : %@", m)
                }
                step = .fallback(archive, reason)
            } catch {
                step = .fallback(archive, L10n.format("L'envoi a échoué : %@", error.localizedDescription))
            }
        }
    }

    private func openGitHub(_ archive: DiagnosticArchive) {
        Task {
            let issue = await library.diagnosticFallbackIssue(for: game, archive: archive)
            switch issue.delivery() {
            case .address(let url, _):
                NSWorkspace.shared.open(url)
            case .clipboard(let url):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(issue.body(), forType: .string)
                NSWorkspace.shared.open(url)
            }
            NSWorkspace.shared.activateFileViewerSelecting([archive.archiveURL])
            openedGitHub = true
        }
    }
}
