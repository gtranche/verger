import Foundation
import Testing

@testable import CidreBridge

/// Un faux `cidre login` qui pose les questions de SteamCMD, sur un vrai terminal
/// (celui que prete `script`) : mot de passe, puis validation mobile ou code.
private func fakeCLI(in dir: URL) throws -> CidreCLI {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let script = dir.appendingPathComponent("cidre")
    try """
        #!/bin/sh
        [ "$1" = login ] || exit 2
        ok() { printf "Logging in user '%s' [U:1:1] to Steam Public...OK\\nWaiting for client config...OK\\nWaiting for user info...OK\\n" "$CIDRE_STEAM_USER"; exit 0; }
        echo "Connexion SteamCMD pour '$CIDRE_STEAM_USER'"
        [ "$CIDRE_STEAM_USER" = memorise ] && { echo "Logging in using cached credentials."; ok; }
        printf "Cached credentials not found.\\n\\npassword: "
        read -r p
        [ "$p" = "mot de passe" ] || { echo; echo "FAILED (Invalid Password)"; exit 5; }
        case "$CIDRE_STEAM_USER" in
          mobile) echo "Please confirm the login in the Steam Mobile app on your phone."; sleep 0.3; ok ;;
          code) printf "Steam Guard code:"; read -r c
                [ "$c" = 4X2QK ] && ok
                echo "FAILED (Two-factor code mismatch)"; exit 5 ;;
          limite) echo "ERROR (Rate Limit Exceeded)"; exit 5 ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)
    return CidreCLI(executable: script)
}

/// Deroule une connexion en repondant aux questions, et rend les evenements vus.
private func login(_ account: String, password: String, code: String = "", in dir: URL) async throws -> [SteamLoginSession.Event] {
    var cli = try fakeCLI(in: dir)
    cli.steamUser = account
    let (stream, continuation) = AsyncStream<SteamLoginSession.Event>.makeStream()
    let session = SteamLoginSession(cli: cli) { continuation.yield($0) }
    try session.start()
    var seen: [SteamLoginSession.Event] = []
    for await event in stream {
        seen.append(event)
        switch event {
        case .passwordRequested: session.send(password)
        case .codeRequested: session.send(code)
        case .succeeded, .failed: continuation.finish()
        case .mobileConfirmationRequested: break
        }
    }
    return seen
}

@Test func connexionSteam() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    #expect(try await login("mobile", password: "mot de passe", in: dir)
        == [.passwordRequested, .mobileConfirmationRequested, .succeeded])
    #expect(try await login("code", password: "mot de passe", code: "4X2QK", in: dir)
        == [.passwordRequested, .codeRequested, .succeeded])
    // session deja memorisee : SteamCMD ne demande rien
    #expect(try await login("memorise", password: "", in: dir) == [.succeeded])

    #expect(try await login("mobile", password: "faux", in: dir)
        == [.passwordRequested, .failed("Identifiant ou mot de passe incorrect.")])
    #expect(try await login("code", password: "mot de passe", code: "00000", in: dir)
        == [.passwordRequested, .codeRequested, .failed("Code Steam Guard incorrect.")])
    #expect(try await login("limite", password: "mot de passe", in: dir).last
        == .failed("Trop de tentatives : Steam demande de patienter avant de réessayer."))
}

@Test func laRaisonNePorteJamaisLaSortieBrute() {
    // une sortie inattendue (qui pourrait contenir la saisie) n'est pas recopiee
    #expect(SteamLoginSession.reason(in: "password: hunter2\nquelque chose a casse")
        == "Steam a refusé la connexion.")
    #expect(SteamLoginSession.reason(in: "failed (account logon denied)")
        == "Steam a refusé la connexion (account logon denied).")
}
