import CidreBridge
import SwiftUI

/// Ce qu'on signale : un jeu (l'incident va chez Cidre), ou l'application.
struct ReportRequest: Identifiable {
    let id = UUID()
    var game: Game?
    var error: String?
}

/// « Signaler un problème » : Verger prepare un incident GitHub et le montre ;
/// c'est l'utilisateur qui l'envoie, depuis la page de GitHub.
struct ReportSheet: View {
    let request: ReportRequest
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var prepared: LibraryModel.PreparedReport?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Signaler un problème", systemImage: "exclamationmark.bubble")
                .font(.headline)
            Text("Verger prépare l'incident, c'est toi qui l'envoies : GitHub s'ouvre avec ce texte, tu le complètes et tu le publies. Il faut un compte GitHub.")
                .fixedSize(horizontal: false, vertical: true)
            Label("L'incident sera public. Ton nom de session, tes identifiants Steam et le nom de ton Mac ont été retirés : relis quand même avant d'envoyer.", systemImage: "eye")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let prepared {
                ScrollView {
                    Text(verbatim: prepared.report.body())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                if let attachment = prepared.attachment {
                    HStack {
                        Text("Une adresse web ne porte que la fin du journal. Pour le joindre en entier, glisse ce fichier dans l'incident :")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Afficher le fichier") {
                            NSWorkspace.shared.activateFileViewerSelecting([attachment])
                        }
                    }
                }
            } else {
                ProgressView("Préparation du rapport…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? "Copié" : "Copier le rapport") {
                    guard let prepared else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prepared.report.body(), forType: .string)
                    copied = true
                }
                .disabled(prepared == nil)
                Button("Ouvrir sur GitHub") {
                    guard let prepared else { return }
                    NSWorkspace.shared.open(prepared.report.url())
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(prepared == nil)
            }
        }
        .padding(20)
        .frame(width: 600, height: 560)
        .task {
            prepared = await library.prepareReport(game: request.game, error: request.error)
        }
    }
}
