import SwiftUI

/// Le diagnostic de Cidre : ce qui est installe, ce qui tourne, et si Wine
/// demarre -- avec ses messages d'erreur. Un texte a copier, pour depanner une
/// machine qu'on n'a pas sous les yeux.
struct DiagnosticSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var copied = false
    @State private var run = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diagnostic de Cidre", systemImage: "stethoscope")
                .font(.headline)
            Text("Verger vérifie l'installation, puis essaie de faire démarrer Wine, un programme x86-64 et le pilote graphique. Rien de ce qui tourne déjà n'est arrêté.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let text {
                ScrollView {
                    Text(verbatim: text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            } else {
                ProgressView("Diagnostic en cours… Il peut durer une minute.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Text("Ton nom de session, tes identifiants Steam et le nom de ton Mac sont retirés de ce texte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Relancer") {
                    text = nil
                    copied = false
                    run += 1
                }
                .disabled(text == nil)
                Button(copied ? "Copié" : "Copier") {
                    guard let text else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(text == nil)
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 760, height: 580)
        .task(id: run) {
            text = await library.diagnostic()
        }
    }
}
