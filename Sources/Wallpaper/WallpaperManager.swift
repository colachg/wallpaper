import AppKit

@MainActor @Observable
class WallpaperManager {
    var currentTitle = ""
    var currentCopyright = "colachg"
    var errorMessage: String?
    var isLoading = false
    var currentIndex = 0
    var previewImage: NSImage?
    private(set) var images: [BingImage] = []

    private var timer: Timer?

    var locale: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BingWallpaper")
    }

    var hasPrevious: Bool { currentIndex < images.count - 1 }
    var hasNext: Bool { currentIndex > 0 }

    // MARK: - Lifecycle

    /// Start the manager: fetch all images and schedule hourly refresh
    func start() {
        guard timer == nil else { return }
        Task { await loadAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    // MARK: - Fetching

    /// Initial load: fetch the last 16 days of wallpapers (2 API calls of 8)
    private func loadAll() async {
        isLoading = true
        errorMessage = nil
        do {
            var allImages: [BingImage] = []
            for idx in stride(from: 0, to: 16, by: 8) {
                let fetched = try await fetchImages(idx: idx, count: 8)
                allImages.append(contentsOf: fetched)
            }
            guard !allImages.isEmpty else { throw WallpaperError.noImages }
            images = allImages
            currentIndex = 0
            try await applyWallpaper(at: 0)
            cleanOldCache()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Refresh: check for the latest image only, insert if new, then apply it
    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await fetchImages(idx: 0, count: 1)
            if let latest = fetched.first {
                if images.first?.startdate != latest.startdate {
                    images.insert(latest, at: 0)
                    cleanOldCache()
                }
                currentIndex = 0
                try await applyWallpaper(at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetch images from Bing API, bypassing HTTP cache
    private func fetchImages(idx: Int, count: Int) async throws -> [BingImage] {
        let url = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=\(idx)&n=\(count)&mkt=\(locale)"
        var request = URLRequest(url: URL(string: url)!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BingResponse.self, from: data).images
    }

    // MARK: - Navigation

    func previous() async {
        guard hasPrevious else { return }
        currentIndex += 1
        do { try await applyWallpaper(at: currentIndex) }
        catch { errorMessage = error.localizedDescription }
    }

    func next() async {
        guard hasNext else { return }
        currentIndex -= 1
        do { try await applyWallpaper(at: currentIndex) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Wallpaper

    /// Download the image (if not cached) and set it as wallpaper on all screens
    private func applyWallpaper(at index: Int) async throws {
        let image = images[index]
        let localURL = try await downloadImage(image)

        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(localURL, for: screen)
        }

        currentTitle = image.title
        currentCopyright = image.copyright
        previewImage = NSImage(contentsOf: localURL)
    }

    /// Download UHD image to cache, skip if already exists
    private func downloadImage(_ image: BingImage) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("\(image.startdate)_\(locale)_UHD.jpg")
        if FileManager.default.fileExists(atPath: localURL.path) { return localURL }

        let url = URL(string: "https://www.bing.com\(image.urlbase)_UHD.jpg")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !data.isEmpty else { throw WallpaperError.downloadFailed }

        try data.write(to: localURL)
        return localURL
    }

    // MARK: - Cache

    /// Remove cached images older than 16 days
    private func cleanOldCache() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-16 * 86400)
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files {
            if let created = (try? fm.attributesOfItem(atPath: file.path))?[.creationDate] as? Date,
               created < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
