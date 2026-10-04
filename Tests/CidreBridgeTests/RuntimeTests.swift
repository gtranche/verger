import Foundation
import Testing

@testable import CidreBridge

@Test func compareLesVersions() {
    let release = RuntimeRelease(version: "1.10.0", archive: URL(fileURLWithPath: "/x"))
    #expect(release.isNewer(than: "1.9.3"))
    #expect(release.isNewer(than: "v1.2"))
    #expect(!release.isNewer(than: "1.10.0"))
    #expect(!release.isNewer(than: "1.10"))
    #expect(!release.isNewer(than: "2.0.0"))
}

@Test func litLaDerniereRelease() throws {
    let json = """
        {"tag_name":"v1.1.0","assets":[
          {"name":"cidre-runtime.tar.zst","size":580000000,"browser_download_url":"https://exemple.test/r.tar.zst"},
          {"name":"cidre-runtime.tar.xz","size":560000000,"browser_download_url":"https://exemple.test/r.tar.xz"}]}
        """
    let release = try RuntimeInstaller.parseRelease(Data(json.utf8))
    #expect(release == RuntimeRelease(
        version: "1.1.0", archive: URL(string: "https://exemple.test/r.tar.xz")!, sizeBytes: 560_000_000))

    // une release d'avant Verger n'a que le .tar.zst : on le dit, on ne l'installe pas
    let old = #"{"tag_name":"v1.0.0","assets":[{"name":"cidre-runtime.tar.zst","size":1,"browser_download_url":"https://exemple.test/r.tar.zst"}]}"#
    #expect(throws: RuntimeError.self) { try RuntimeInstaller.parseRelease(Data(old.utf8)) }
}

@Test func decodeLEtatDuRuntime() throws {
    let json = #"{"version":"1.1.0","racine":"/x/cidre","runtime":true,"prefixe":false,"steamcmd":true,"jeu_en_cours":false,"prerequis":{"spirv_tools":true,"freetype":false}}"#
    let status = try JSONDecoder().decode(RuntimeStatus.self, from: Data(json.utf8))
    #expect(status.version == "1.1.0" && !status.isDevelopmentCheckout)
    #expect(status.runtimePresent && !status.prefixReady)
    #expect(status.prerequisites.missing == ["freetype"])
}

/// Bout en bout sur une fausse archive : decompression, `cidre setup`, CLI rendue.
@Test func installeUneFausseArchive() async throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let stage = dir.appendingPathComponent("stage/cidre")
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    try """
        #!/bin/sh
        R=$(cd "$(dirname "$0")" && pwd)
        case "$1" in
          setup) echo "== 1/2 Pilote Vulkan =="; echo "  detail"; echo "== 2/2 Prefixe Wine =="
                 [ -f "$R/CASSE" ] && { echo "wineboot a plante"; exit 4; }
                 touch "$R/configure" ;;
          status) printf '{"version":"%s","racine":"%s","runtime":true,"prefixe":true,"steamcmd":false,"jeu_en_cours":false,"prerequis":{"spirv_tools":true,"freetype":true}}\\n' "$(cat "$R/VERSION")" "$R" ;;
        esac
        """.write(to: stage.appendingPathComponent("cidre"), atomically: true, encoding: .utf8)
    try "1.1.0\n".write(to: stage.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)

    let archive = dir.appendingPathComponent("cidre-runtime.tar.xz")
    let tar = try await RuntimeInstaller.run(
        "/usr/bin/tar", ["-c", "--xz", "-f", archive.path, "-C", stage.deletingLastPathComponent().path, "cidre"])
    #expect(tar.status == 0)

    // l'archive donnee par VERGER_RUNTIME_URL remplace la release publiee
    let release = try await RuntimeInstaller.latestRelease(
        environment: ["VERGER_RUNTIME_URL": archive.path, "VERGER_RUNTIME_VERSION": "1.1.0"])
    #expect(release.archive == archive && release.version == "1.1.0")

    let installer = RuntimeInstaller(home: dir.appendingPathComponent("Application Support/Cidre"))
    #expect(installer.installedCLI == nil)
    let steps = Steps()
    let cli = try await installer.install(release) { steps.add($0) }
    #expect(cli.executable.path == installer.home.appendingPathComponent("cidre/cidre").path)
    #expect(fm.fileExists(atPath: installer.home.appendingPathComponent("cidre/configure").path))
    #expect(steps.all.contains(.extracting))
    #expect(steps.all.contains(.configuring("1/2 Pilote Vulkan")))
    #expect(steps.all.last == .configuring("2/2 Prefixe Wine"))
    #expect(try await cli.status().version == "1.1.0")

    // une mise a jour decompresse par-dessus : ce que l'archive ne contient pas reste
    let save = installer.home.appendingPathComponent("cidre/wine/pfx/sauvegarde")
    try fm.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "partie".write(to: save, atomically: true, encoding: .utf8)
    _ = try await installer.install(release) { _ in }
    #expect(try String(contentsOf: save, encoding: .utf8) == "partie")

    // un `cidre setup` qui echoue remonte avec la fin de sa sortie
    try "".write(to: installer.home.appendingPathComponent("cidre/CASSE"), atomically: true, encoding: .utf8)
    do {
        _ = try await installer.install(release) { _ in }
        Issue.record("un setup en echec doit lever")
    } catch let RuntimeError.setupFailed(detail) {
        #expect(detail.contains("wineboot a plante"))
    }

    // une archive qui ne contient pas Cidre
    let other = dir.appendingPathComponent("autre.tar.xz")
    _ = try await RuntimeInstaller.run("/usr/bin/tar", ["-c", "--xz", "-f", other.path, "-C", dir.path, "stage"])
    let empty = RuntimeInstaller(home: dir.appendingPathComponent("vide"))
    await #expect(throws: RuntimeError.self) {
        _ = try await empty.install(RuntimeRelease(version: "1", archive: other)) { _ in }
    }
}

private final class Steps: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RuntimeInstaller.Step] = []
    func add(_ value: RuntimeInstaller.Step) { lock.lock(); values.append(value); lock.unlock() }
    var all: [RuntimeInstaller.Step] { lock.lock(); defer { lock.unlock() }; return values }
}
