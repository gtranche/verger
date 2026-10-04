import AppKit
import CidreBridge
import Observation

/// La mise a jour de Verger lui-meme, par ses releases GitHub. Separee de celle
/// de Cidre : un correctif d'interface ne retelecharge rien du runtime.
@MainActor
@Observable
final class AppUpdateModel {
    enum State: Equatable {
        case idle
        case checking
        case downloading(doneBytes: Int64, totalBytes: Int64)
        case failed(String)
    }

    /// La version de cette application, ou `nil` hors d'un bundle (`swift run`).
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    private(set) var latest: AppRelease?
    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    /// Une version plus recente est publiee, et cette application peut se remplacer.
    var available: AppRelease? {
        guard let latest, let currentVersion, latest.isNewer(than: currentVersion) else { return nil }
        return latest
    }

    func check() async {
        guard currentVersion != nil, state != .checking else { return }
        state = .checking
        do {
            latest = try await AppUpdater.latestRelease()
            lastCheck = Date()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Telecharge la nouvelle version, la met a la place de celle-ci et relance.
    func install() async {
        guard let release = available else { return }
        let app = Bundle.main.bundleURL
        state = .downloading(doneBytes: 0, totalBytes: release.sizeBytes)
        do {
            try await AppUpdater.install(release, replacing: app) { done, total in
                Task { @MainActor in
                    if case .downloading = self.state {
                        self.state = .downloading(doneBytes: done, totalBytes: total > 0 ? total : release.sizeBytes)
                    }
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        // La nouvelle version est en place : on la lance une fois celle-ci sortie.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
