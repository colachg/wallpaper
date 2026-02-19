import AppKit

enum UpdateState: Equatable {
    case idle
    case downloading(progress: Double)
    case installing
    case failed(String)
}

@MainActor @Observable
final class UpdateChecker {
    var updateAvailable = false
    var latestVersion: String?
    var updateState: UpdateState = .idle

    private var timer: Timer?
    private var releaseURL: URL?
    private var downloadAssetURL: URL?

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        Task { await checkForUpdate() }
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { await self?.checkForUpdate() }
        }
    }

    // MARK: - Update Check

    func checkForUpdate() async {
        do {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/colachg/wallpaper/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name

            let currentVersion =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if Self.isNewer(remote: remoteVersion, than: currentVersion) {
                latestVersion = remoteVersion
                releaseURL = URL(string: release.html_url)
                downloadAssetURL = release.assets
                    .first(where: { $0.name == "Wallpaper.app.zip" })
                    .flatMap { URL(string: $0.browser_download_url) }
                updateAvailable = true
            } else {
                updateAvailable = false
            }
        } catch {
            // Fail silently — update checking should never disrupt the app
        }
    }

    // MARK: - Auto Update

    func performUpdate() {
        guard Bundle.main.bundlePath.hasSuffix(".app"),
              let assetURL = downloadAssetURL
        else {
            openReleasePage()
            return
        }

        Task { await downloadAndInstall(from: assetURL) }
    }

    func openReleasePage() {
        guard let url = releaseURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func downloadAndInstall(from url: URL) async {
        updateState = .downloading(progress: 0)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("Wallpaper.app.zip")

            try await downloadFile(from: url, to: zipPath)

            updateState = .installing

            let extractDir = tempDir.appendingPathComponent("extracted")
            try await extract(zipPath: zipPath, to: extractDir)
            try replaceAndRelaunch(extractDir: extractDir, tempDir: tempDir)
        } catch {
            await handleUpdateFailure(tempDir: tempDir)
        }
    }

    private func downloadFile(from url: URL, to destination: URL) async throws {
        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateState = .downloading(progress: progress)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (downloadedURL, _) = try await session.download(for: URLRequest(url: url))
        try FileManager.default.moveItem(at: downloadedURL, to: destination)
    }

    private nonisolated func extract(zipPath: URL, to extractDir: URL) async throws {
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zipPath.path, extractDir.path]
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.extractionFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func replaceAndRelaunch(extractDir: URL, tempDir: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: extractDir, includingPropertiesForKeys: nil)
        guard let newAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.extractionFailed
        }

        let currentAppURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let parentDir = currentAppURL.deletingLastPathComponent()

        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            throw UpdateError.noWritePermission
        }

        let backupURL = currentAppURL.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: backupURL)

        do {
            try FileManager.default.moveItem(at: currentAppURL, to: backupURL)
            try FileManager.default.moveItem(at: newAppURL, to: currentAppURL)
        } catch {
            try? FileManager.default.moveItem(at: backupURL, to: currentAppURL)
            throw UpdateError.replaceFailed
        }

        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.removeItem(at: tempDir)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", currentAppURL.path]
        try task.run()

        NSApplication.shared.terminate(nil)
    }

    private func handleUpdateFailure(tempDir: URL) async {
        updateState = .failed("Update failed")
        try? FileManager.default.removeItem(at: tempDir)
        try? await Task.sleep(for: .seconds(2))
        openReleasePage()
        updateState = .idle
    }

    // MARK: - Semver Comparison

    nonisolated static func isNewer(remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, currentParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}

// MARK: - Download Progress

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo _: URL
    ) {}

    func urlSession(
        _: URLSession, downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}

// MARK: - Models

private enum UpdateError: Error {
    case extractionFailed
    case noWritePermission
    case replaceFailed
}

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
}

struct GitHubRelease: Codable {
    let tag_name: String
    let html_url: String
    let assets: [GitHubAsset]
}
