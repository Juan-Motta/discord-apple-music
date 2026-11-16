import AppKit
import PresenceKit
import Security

/// Downloads a release, checks it was signed by the same developer as this app, and swaps it in.
enum AppInstaller {
    enum Failure: LocalizedError {
        case notWritable
        case download
        case unpack
        case untrusted

        var errorDescription: String? {
            switch self {
            case .notWritable: "Can't replace the app in its folder. Download the update instead."
            case .download: "The download failed. Try again later."
            case .unpack: "The download is not a valid app archive."
            case .untrusted: "The download is not signed by this app's developer, so it was not installed."
            }
        }
    }

    static let appName = "Discord Apple Music.app"

    /// Replaces the running app with `update`. The running process keeps working until it relaunches.
    static func install(_ update: AvailableUpdate) async throws {
        let target = Bundle.main.bundleURL
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw Failure.notWritable
        }

        // Unpack next to the app (same volume), so the final swap is a rename.
        let work = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? fileManager.removeItem(at: work) }

        let (download, response) = try await URLSession.shared.download(from: update.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let archive = work.appendingPathComponent("update.zip")
        try fileManager.moveItem(at: download, to: archive)

        guard run("/usr/bin/ditto", "-x", "-k", archive.path, work.path) else { throw Failure.unpack }
        let newApp = work.appendingPathComponent(appName)
        guard fileManager.fileExists(atPath: newApp.path) else { throw Failure.unpack }

        try verify(newApp)
        _ = try fileManager.replaceItemAt(target, withItemAt: newApp)
    }

    /// Accepts only a valid Developer ID signature from this app's own team, covering every
    /// nested binary and architecture. A modified or foreign download fails here.
    static func verify(_ app: URL) throws {
        guard let team = ownTeamID() else { throw Failure.untrusted }
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.discord-apple-music"
        let rule = """
            anchor apple generic and identifier "\(bundleID)" \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] \
            and certificate leaf[subject.OU] = "\(team)"
            """
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess, let requirement
        else { throw Failure.untrusted }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw Failure.untrusted }
    }

    /// The Team ID this app is signed with; nil for unsigned development builds.
    static func ownTeamID() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Opens the (now updated) app once this process has exited, then quits.
    @MainActor
    static func relaunch() {
        let wait = Process()
        wait.executableURL = URL(fileURLWithPath: "/bin/sh")
        wait.arguments = [
            "-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
            Bundle.main.bundlePath,
        ]
        try? wait.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: String...) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
