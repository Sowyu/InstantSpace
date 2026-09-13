import AppKit
import CryptoKit
import Foundation

/// Self-updater backed by GitHub Releases. Checks daily, downloads the DMG,
/// verifies sha256 against GitHub's asset digest and the bundle's code signature,
/// swaps the app bundle in place, then relaunches.
final class Updater {
    static let shared = Updater()

    struct Release {
        let version: String
        let downloadURL: URL
        let sha256: String?
    }

    enum State {
        case idle
        case checking
        case available(Release)
        case installing
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?

    private let repo = "Sowyu/InstantSpace"
    private let assetName = "SPACE.dmg"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let lastCheckKey = "lastUpdateCheck"
    private var timer: Timer?

    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Scheduling

    func startDailyChecks() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        let due = max(5, checkInterval - Date().timeIntervalSince(last))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: due, repeats: false) { [weak self] _ in
            self?.check(interactive: false)
            self?.startDailyChecks()
        }
    }

    // MARK: Check

    func check(interactive: Bool) {
        if case .installing = state { return }
        if case .checking = state { return }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        fetchLatestRelease { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release):
                if Self.isNewer(release.version, than: self.currentVersion) {
                    self.state = .available(release)
                    if interactive { self.offerInstall(release) }
                } else {
                    self.state = .idle
                    if interactive {
                        self.alert("SPACE \(self.currentVersion) is up to date.", style: .informational)
                    }
                }
            case .failure(let error):
                self.state = .idle
                if interactive { self.alert("Update check failed: \(error.localizedDescription)") }
            }
        }
    }

    private func fetchLatestRelease(_ completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SPACE/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Release, Error>
            do {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw UpdateError("GitHub returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                guard let data,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let assets = json["assets"] as? [[String: Any]],
                      let asset = assets.first(where: { $0["name"] as? String == self.assetName }),
                      let urlString = asset["browser_download_url"] as? String,
                      let url = URL(string: urlString)
                else {
                    throw UpdateError("Latest release has no \(self.assetName) asset")
                }
                let digest = (asset["digest"] as? String)?.replacingOccurrences(of: "sha256:", with: "")
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                result = .success(Release(version: version, downloadURL: url, sha256: digest))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Install

    private func offerInstall(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SPACE \(release.version) is available"
        alert.informativeText = "You have \(currentVersion). Install and relaunch now?"
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            install()
        }
    }

    func install() {
        guard case .available(let release) = state else { return }
        state = .installing

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let newApp = try downloadAndStage(release)
                try verify(newApp, expectedVersion: release.version)
                try swapIn(newApp)
                DispatchQueue.main.async { self.relaunch() }
            } catch {
                DispatchQueue.main.async {
                    self.state = .available(release)
                    self.alert("Update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func downloadAndStage(_ release: Release) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPACE-update-\(release.version)", isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let dmg = work.appendingPathComponent(assetName)
        let data = try downloadSync(release.downloadURL)
        if let expected = release.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw UpdateError("Downloaded file hash does not match GitHub's digest") }
        } else {
            NSLog("Updater: GitHub provided no digest, skipping hash check")
        }
        try data.write(to: dmg)

        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify",
                                     "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let staged = work.appendingPathComponent("SPACE.app", isDirectory: true)
        try FileManager.default.copyItem(at: mount.appendingPathComponent("SPACE.app"), to: staged)
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    private func downloadSync(_ url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("SPACE/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Data, Error> = .failure(UpdateError("No response"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                outcome = .failure(error)
            } else if let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                outcome = .success(data)
            } else {
                outcome = .failure(UpdateError("Download failed with HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try outcome.get()
    }

    private func verify(_ app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app) else { throw UpdateError("Downloaded app is not a valid bundle") }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("Downloaded app has bundle id \(bundle.bundleIdentifier ?? "nil")")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version == expectedVersion else {
            throw UpdateError("Downloaded app is version \(version ?? "nil"), expected \(expectedVersion)")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    private func swapIn(_ newApp: URL) throws {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        let dir = current.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: dir.path) else {
            throw UpdateError("Cannot write to \(dir.path). Move SPACE to Applications and try again.")
        }
        let old = dir.appendingPathComponent(".SPACE.app.old-\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(at: old)
        try fm.moveItem(at: current, to: old)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            try? fm.moveItem(at: old, to: current)
            throw error
        }
        try? fm.removeItem(at: old)
    }

    private func relaunch() {
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private func alert(_ message: String, style: NSAlert.Style = .warning) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.runModal()
    }

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
