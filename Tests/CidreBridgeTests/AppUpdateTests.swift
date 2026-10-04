import Foundation
import Testing

@testable import CidreBridge

@Test func litLaDerniereReleaseDeVerger() throws {
    let json = """
        {"tag_name":"v0.3.0","assets":[
          {"name":"Verger.zip","size":900000,"browser_download_url":"https://exemple.test/Verger.zip"}]}
        """
    let release = try AppUpdater.parseRelease(Data(json.utf8))
    #expect(release == AppRelease(version: "0.3.0", archive: URL(string: "https://exemple.test/Verger.zip")!, sizeBytes: 900_000))
    #expect(release.isNewer(than: "0.2.9") && !release.isNewer(than: "0.3.0") && !release.isNewer(than: "1.0"))

    #expect(throws: AppUpdateError.self) {
        try AppUpdater.parseRelease(Data(#"{"tag_name":"v0.3.0","assets":[]}"#.utf8))
    }
}

/// Une fausse application : un executable qui dit sa version, signe ad hoc.
private func makeApp(at url: URL, saying version: String) async throws {
    let fm = FileManager.default
    let macos = url.appendingPathComponent("Contents/MacOS")
    try fm.createDirectory(at: macos, withIntermediateDirectories: true)
    let exe = macos.appendingPathComponent("Verger")
    try "#!/bin/sh\necho \(version)\n".write(to: exe, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleExecutable</key><string>Verger</string><key>CFBundleIdentifier</key><string>test.verger</string></dict></plist>
        """.write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
    let sign = try await RuntimeInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
    #expect(sign.status == 0)
}

private func version(of app: URL) async throws -> String {
    let said = Said()
    _ = try await RuntimeInstaller.run(app.appendingPathComponent("Contents/MacOS/Verger").path, []) { said.set($0) }
    return said.value
}

private final class Said: @unchecked Sendable {
    private let lock = NSLock()
    private var line = ""
    func set(_ value: String) { lock.lock(); line = value; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return line }
}

@Test func remplaceLApplicationParLaNouvelle() async throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    // l'application en place, et la release : un zip de la nouvelle
    let installed = dir.appendingPathComponent("Applications/Verger.app")
    try await makeApp(at: installed, saying: "0.1.0")
    let fresh = dir.appendingPathComponent("nouvelle/Verger.app")
    try await makeApp(at: fresh, saying: "0.2.0")
    let zip = dir.appendingPathComponent("Verger.zip")
    #expect(try await RuntimeInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", fresh.path, zip.path]).status == 0)

    try await AppUpdater.install(AppRelease(version: "0.2.0", archive: zip), replacing: installed)
    #expect(try await version(of: installed) == "0.2.0")
    // rien ne traine a cote de l'application
    #expect(try fm.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path) == ["Verger.app"])

    // un zip sans Verger.app : l'application en place n'est pas touchee
    let other = dir.appendingPathComponent("autre.zip")
    _ = try await RuntimeInstaller.run("/usr/bin/ditto", ["-c", "-k", dir.appendingPathComponent("nouvelle").path, other.path])
    try await makeApp(at: dir.appendingPathComponent("vide/Autre.app"), saying: "9")
    let wrong = dir.appendingPathComponent("faux.zip")
    _ = try await RuntimeInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", dir.appendingPathComponent("vide/Autre.app").path, wrong.path])
    await #expect(throws: AppUpdateError.self) {
        try await AppUpdater.install(AppRelease(version: "9", archive: wrong), replacing: installed)
    }
    #expect(try await version(of: installed) == "0.2.0")

    // une application alteree apres signature est refusee
    let tampered = dir.appendingPathComponent("alteree/Verger.app")
    try await makeApp(at: tampered, saying: "0.3.0")
    try "#!/bin/sh\necho pirate\n".write(
        to: tampered.appendingPathComponent("Contents/MacOS/Verger"), atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tampered.appendingPathComponent("Contents/MacOS/Verger").path)
    let bad = dir.appendingPathComponent("alteree.zip")
    _ = try await RuntimeInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", tampered.path, bad.path])
    await #expect(throws: AppUpdateError.self) {
        try await AppUpdater.install(AppRelease(version: "0.3.0", archive: bad), replacing: installed)
    }
    #expect(try await version(of: installed) == "0.2.0")

    // hors d'une application (.app), on ne remplace rien
    await #expect(throws: AppUpdateError.self) {
        try await AppUpdater.install(AppRelease(version: "1", archive: zip), replacing: dir.appendingPathComponent("Verger"))
    }
}

/// La vraie release de Verger, depuis GitHub, sur une COPIE de l'application.
///   VERGER_ESSAI_MAJ=/dossier/jetable/Verger.app Scripts/test.sh --filter metAJourDepuisGitHub
@Test(.enabled(if: ProcessInfo.processInfo.environment["VERGER_ESSAI_MAJ"] != nil))
func metAJourDepuisGitHub() async throws {
    let app = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VERGER_ESSAI_MAJ"]!)
    let release = try await AppUpdater.latestRelease()
    #expect(release.archive.lastPathComponent == AppUpdater.assetName)
    try await AppUpdater.install(release, replacing: app)
    let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    #expect(plist?["CFBundleShortVersionString"] as? String == release.version)
    #expect(try await RuntimeInstaller.run("/usr/bin/codesign", ["--verify", "--deep", app.path]).status == 0)
    print("mis a jour : Verger \(release.version)")
}

@Test func steamGridDB() throws {
    let found: [SteamGridDB.Match] = try SteamGridDB.decode(Data("""
        {"success":true,"data":[{"id":2254,"name":"Dead Cells","types":["steam"],"verified":true},{"id":9,"name":"Dead Cells Demo"}]}
        """.utf8))
    #expect(found == [SteamGridDB.Match(id: 2254, name: "Dead Cells"), SteamGridDB.Match(id: 9, name: "Dead Cells Demo")])

    let grids: [SteamGridDB.Grid] = try SteamGridDB.decode(Data("""
        {"success":true,"data":[{"id":7,"url":"https://cdn2.steamgriddb.com/grid/a.png","thumb":"https://cdn2.steamgriddb.com/thumb/a.jpg","width":600,"height":900}]}
        """.utf8))
    #expect(grids.first?.url.pathExtension == "png")
    // un jeu inconnu : `data` absent, pas une erreur
    let none: [SteamGridDB.Grid] = try SteamGridDB.decode(Data(#"{"success":false}"#.utf8))
    #expect(none.isEmpty)

    // la cle part dans l'en-tete, jamais dans l'adresse
    let api = SteamGridDB(key: "  cle-secrete\n")
    let request = api.request("grids/game/2254", query: "dimensions=600x900")
    #expect(request.url?.absoluteString == "https://www.steamgriddb.com/api/v2/grids/game/2254?dimensions=600x900")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cle-secrete")
}

@Test func sansCleSteamGridDBNeDemandeRienAuReseau() async {
    await #expect(throws: SteamGridDB.Failure.missingKey) { _ = try await SteamGridDB(key: " ").search("Dead Cells") }
}
