import Cocoa

/// Downloads a release and replaces the installed app with it.
///
/// The app reads every keystroke, so running a binary fetched from the network
/// is only acceptable if we can prove it is ours. Before anything is installed,
/// the download must satisfy *this* app's designated requirement — which pins
/// the signing certificate, so only a build signed with the same private key
/// passes. HTTPS alone would not be enough.
///
/// A consequence worth knowing: an ad-hoc signed copy has a designated
/// requirement naming its own binary hash, which no other build can match, so
/// it can never self-update. That is the safe direction to fail in.
enum Updater {

    enum Failure: LocalizedError {
        case notInstalled
        case download
        case mount
        case untrusted
        case install(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Only a copy in Applications can update itself."
            case .download:
                return "Could not download the update."
            case .mount:
                return "Could not open the downloaded disk image."
            case .untrusted:
                return "The download isn't signed with the same certificate as this app, so it wasn't installed."
            case .install(let reason):
                return "Could not replace the app: \(reason)"
            }
        }
    }

    private static let installPath = "/Applications/LangSwitcher.app"

    static func downloadURL(for version: String) -> URL? {
        URL(string: "https://github.com/vozivrom/lang-switcher/releases/download/"
            + "v\(version)/LangSwitcher-\(version).dmg")
    }

    /// Downloads, verifies, installs, and relaunches. Calls back on the main
    /// queue; on success the app is about to be replaced and quit.
    static func install(version: String, completion: @escaping (Result<Void, Error>) -> Void) {
        func finish(_ result: Result<Void, Error>) {
            DispatchQueue.main.async { completion(result) }
        }

        guard Instance.isInstalled else { return finish(.failure(Failure.notInstalled)) }
        guard let url = downloadURL(for: version) else { return finish(.failure(Failure.download)) }

        URLSession.shared.downloadTask(with: url) { temporary, response, _ in
            guard let temporary = temporary,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                return finish(.failure(Failure.download))
            }
            // The temporary file is removed as soon as this handler returns.
            let dmg = FileManager.default.temporaryDirectory
                .appendingPathComponent("LangSwitcher-\(version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            do {
                try FileManager.default.moveItem(at: temporary, to: dmg)
            } catch {
                return finish(.failure(Failure.download))
            }

            do {
                try installFrom(dmg: dmg)
                finish(.success(()))
                relaunch()
            } catch {
                finish(.failure(error))
            }
            try? FileManager.default.removeItem(at: dmg)
        }.resume()
    }

    private static func installFrom(dmg: URL) throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("LangSwitcherUpdate")
        try? FileManager.default.removeItem(at: mountPoint)
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        guard run("/usr/bin/hdiutil",
                  ["attach", dmg.path, "-nobrowse", "-readonly",
                   "-mountpoint", mountPoint.path]) else {
            throw Failure.mount
        }
        // Leaving a volume mounted leaves a second copy of the app around, which
        // makes macOS invalidate the Accessibility grant.
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? FileManager.default.removeItem(at: mountPoint)
        }

        let newApp = mountPoint.appendingPathComponent("LangSwitcher.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw Failure.mount }
        guard matchesOurSignature(newApp) else { throw Failure.untrusted }

        let destination = URL(fileURLWithPath: installPath)
        let staging = URL(fileURLWithPath: "/Applications/.LangSwitcher-update.app")
        try? FileManager.default.removeItem(at: staging)
        do {
            // Copy first, then swap, so a failed copy can't leave no app at all.
            try FileManager.default.copyItem(at: newApp, to: staging)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw Failure.install(error.localizedDescription)
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
    }

    /// True when the bundle satisfies this app's own designated requirement.
    static func matchesOurSignature(_ app: URL) -> Bool {
        matches(app, requirementOf: Bundle.main.bundleURL)
    }

    /// Whether `app` satisfies the designated requirement of `reference`.
    /// Split out from `matchesOurSignature` so it can be tested against known
    /// good and known bad bundles.
    static func matches(_ app: URL, requirementOf reference: URL) -> Bool {
        var ourCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(reference as CFURL, [], &ourCode) == errSecSuccess,
              let ourCode = ourCode else { return false }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(ourCode, [], &requirement) == errSecSuccess,
              let requirement = requirement else { return false }

        var candidate: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess,
              let candidate = candidate else { return false }

        return SecStaticCodeCheckValidity(candidate, [], requirement) == errSecSuccess
    }

    /// Waits for this process to exit before opening the new copy — the
    /// single-instance guard would otherwise make the new one quit immediately.
    private static func relaunch() {
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; "
            + "do sleep 0.2; done; open \(installPath)"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()

        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
