import CidreBridge
import Observation
import SwiftUI

/// Le deroulement d'une connexion Steam : ce que SteamCMD demande, dans l'ordre.
@MainActor
@Observable
final class LoginModel {
    enum Phase: Equatable {
        case form
        case connecting
        case code
        case mobileConfirmation
        case done
    }

    var account = ""
    var password = ""
    var code = ""
    private(set) var phase: Phase = .form
    private(set) var error: String?
    private var session: SteamLoginSession?

    func start(with cli: CidreCLI) {
        var cli = cli
        cli.steamUser = account.trimmingCharacters(in: .whitespaces)
        error = nil
        let session = SteamLoginSession(cli: cli) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        do {
            try session.start()
            self.session = session
            phase = .connecting
        } catch {
            self.error = error.localizedDescription
        }
    }

    func submitCode() {
        session?.send(code.trimmingCharacters(in: .whitespaces))
        code = ""
        phase = .connecting
    }

    func cancel() {
        session?.cancel()
        session = nil
        password = ""
        phase = .form
    }

    private func handle(_ event: SteamLoginSession.Event) {
        switch event {
        case .passwordRequested:
            // Le mot de passe part a SteamCMD et on l'oublie aussitot.
            session?.send(password)
            password = ""
        case .codeRequested:
            phase = .code
        case .mobileConfirmationRequested:
            phase = .mobileConfirmation
        case .succeeded:
            session = nil
            password = ""
            phase = .done
        case let .failed(reason):
            session = nil
            password = ""
            error = reason
            phase = .form
        }
    }
}

/// La fenetre de connexion a Steam. Verger ne garde ni mot de passe ni jeton :
/// il relaie la saisie a SteamCMD, qui memorise la session.
struct LoginSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var login = LoginModel()

    var body: some View {
        @Bindable var login = login

        VStack(alignment: .leading, spacing: 14) {
            Label("Connexion à Steam", systemImage: "person.badge.key")
                .font(.headline)

            switch login.phase {
            case .form:
                TextField("Identifiant Steam", text: $login.account)
                    .textContentType(.username)
                SecureField("Mot de passe", text: $login.password)
                    .textContentType(.password)
                    .onSubmit(connect)
                if let error = login.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                Text("Ton mot de passe est transmis à SteamCMD, l'outil de Valve, puis oublié. Verger ne le conserve pas ; SteamCMD mémorise la session, tu n'auras pas à le retaper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .connecting:
                waiting("Connexion à Steam…")
            case .mobileConfirmation:
                waiting("Valide la connexion dans l'appli Steam de ton téléphone.")
            case .code:
                Text("Steam Guard demande un code : il est dans l'appli Steam de ton téléphone, ou dans l'e-mail que Steam vient d'envoyer.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Code Steam Guard", text: $login.code)
                    .textContentType(.oneTimeCode)
                    .onSubmit { login.submitCode() }
            case .done:
                Label("Connecté. La session est mémorisée.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                switch login.phase {
                case .form:
                    Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Se connecter", action: connect)
                        .keyboardShortcut(.defaultAction)
                        .disabled(login.account.isEmpty || login.password.isEmpty)
                case .connecting, .mobileConfirmation:
                    Button("Annuler") { login.cancel() }.keyboardShortcut(.cancelAction)
                case .code:
                    Button("Annuler") { login.cancel() }.keyboardShortcut(.cancelAction)
                    Button("Valider") { login.submitCode() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(login.code.isEmpty)
                case .done:
                    Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 380)
        .onAppear {
            login.account = library.steamUser ?? library.runtimeStatus?.steamAccount ?? ""
        }
        .onChange(of: login.phase) { _, phase in
            if phase == .done {
                library.steamUser = login.account.trimmingCharacters(in: .whitespaces)
                Task { await library.loadOwned(refresh: true) }
            }
        }
        .onDisappear { login.cancel() }
    }

    private func connect() {
        guard let cli = library.cli, !login.account.isEmpty, !login.password.isEmpty else { return }
        login.start(with: cli)
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}
