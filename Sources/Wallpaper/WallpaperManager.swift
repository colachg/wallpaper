import AppKit

@MainActor @Observable
class WallpaperManager {
    var currentTitle = ""
    var currentCopyright = "colachg"
    var errorMessage: String?
    var isLoading = false
    var currentIndex = 0
    var previewImage: NSImage?
    var showingFavorites = false
    var favoriteIndex = 0
    var favoritePreviewImage: NSImage?
    private(set) var images: [BingImage] = []

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var activityToken: NSObjectProtocol?

    private let store = PreferencesStore.shared

    var locale: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BingWallpaper")
    }

    var hasPrevious: Bool { !images.isEmpty && currentIndex < images.count - 1 }
    var hasNext: Bool { currentIndex > 0 }

    // MARK: - Like/Dislike/Favorite Computed Properties

    var isCurrentDisliked: Bool {
        guard currentIndex >= 0, currentIndex < images.count else { return false }
        return store.isDisliked(images[currentIndex].startdate)
    }

    var isCurrentFavorited: Bool {
        guard currentIndex >= 0, currentIndex < images.count else { return false }
        return store.isFavorited(images[currentIndex].startdate)
    }

    var favoriteImages: [BingImage] {
        store.preferences.favorites
    }

    var currentFavorite: BingImage? {
        let favs = favoriteImages
        guard !favs.isEmpty, favoriteIndex >= 0, favoriteIndex < favs.count else { return nil }
        return favs[favoriteIndex]
    }

    var hasPreviousFavorite: Bool { !favoriteImages.isEmpty && favoriteIndex < favoriteImages.count - 1 }
    var hasNextFavorite: Bool { favoriteIndex > 0 }

    func showFavorites() async {
        showingFavorites = true
        favoriteIndex = 0
        await applyFavoriteAtIndex()
    }

    func hideFavorites() async {
        showingFavorites = false
        await restoreNonDisliked()
    }

    func previousFavorite() async {
        guard hasPreviousFavorite else { return }
        favoriteIndex += 1
        await applyFavoriteAtIndex()
    }

    func nextFavorite() async {
        guard hasNextFavorite else { return }
        favoriteIndex -= 1
        await applyFavoriteAtIndex()
    }

    func removeCurrentFavorite() async {
        guard let fav = currentFavorite else { return }
        store.removeFavorite(fav)
        if favoriteImages.isEmpty {
            showingFavorites = false
            await restoreNonDisliked()
        } else {
            favoriteIndex = min(favoriteIndex, favoriteImages.count - 1)
            await applyFavoriteAtIndex()
        }
    }

    /// When returning from favorites, ensure we're showing a non-disliked wallpaper
    private func restoreNonDisliked() async {
        if currentIndex >= 0, currentIndex < images.count, store.isDisliked(images[currentIndex].startdate) {
            if let idx = images.firstIndex(where: { !store.isDisliked($0.startdate) }) {
                currentIndex = idx
                do { try await applyWallpaper(at: currentIndex) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    /// Download favorite at current index (if needed), apply to all screens, update preview
    private func applyFavoriteAtIndex() async {
        guard let fav = currentFavorite else {
            favoritePreviewImage = nil
            return
        }
        do {
            let localURL = try await downloadImage(fav)
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(localURL, for: screen)
            }
            favoritePreviewImage = NSImage(contentsOf: localURL)
        } catch {
            errorMessage = error.localizedDescription
            favoritePreviewImage = cachedImage(for: fav)
        }
    }

    // MARK: - Lifecycle

    /// Start the manager: fetch all images and schedule refresh every 6 hours + on wake
    func start() {
        guard timer == nil else { return }
        store.load()
        Task { await loadAll() }

        // Prevent App Nap from deferring the refresh timer
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Periodic wallpaper refresh"
        )

        timer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // On Apple Silicon, screen wake is more reliable than system wake for lid open
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.applyCurrentWallpaper() }
        }
    }

    // MARK: - Fetching

    /// Initial load: fetch the last 10 days of wallpapers (2 API calls)
    private func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            var allImages: [BingImage] = []
            for idx in stride(from: 0, to: 10, by: 5) {
                let fetched = try await fetchImages(idx: idx, count: 5)
                allImages.append(contentsOf: fetched)
            }
            guard !allImages.isEmpty else { throw WallpaperError.noImages }
            images = allImages
            // Apply first non-disliked wallpaper
            if let firstNonDisliked = allImages.firstIndex(where: { !store.isDisliked($0.startdate) }) {
                currentIndex = firstNonDisliked
            } else {
                currentIndex = 0
            }
            try await applyWallpaper(at: currentIndex)
            cleanOldCache()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Refresh: check for the latest image only, insert if new, then apply it
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await fetchImages(idx: 0, count: 1)
            if let latest = fetched.first {
                if images.first?.startdate != latest.startdate {
                    images.insert(latest, at: 0)
                    if images.count > 10 { images.removeLast(images.count - 10) }
                    cleanOldCache()
                }
                // Only auto-apply the latest if it's not disliked
                if !store.isDisliked(latest.startdate) {
                    currentIndex = 0
                    try await applyWallpaper(at: 0)
                }
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
        guard !isLoading, hasPrevious else { return }
        currentIndex += 1
        await showOrApply(at: currentIndex)
    }

    func next() async {
        guard !isLoading, hasNext else { return }
        currentIndex -= 1
        await showOrApply(at: currentIndex)
    }

    /// Preview-only if disliked, otherwise apply as wallpaper
    private func showOrApply(at index: Int) async {
        guard index >= 0, index < images.count else { return }
        let image = images[index]
        if store.isDisliked(image.startdate) {
            do { try await previewOnly(at: index) }
            catch { errorMessage = error.localizedDescription }
        } else {
            do { try await applyWallpaper(at: index) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Download and show in preview without setting as desktop wallpaper
    private func previewOnly(at index: Int) async throws {
        guard index >= 0, index < images.count else { return }
        let image = images[index]
        let localURL = try await downloadImage(image)
        currentTitle = image.title
        currentCopyright = image.copyright
        previewImage = NSImage(contentsOf: localURL)
    }

    // MARK: - Like/Dislike/Favorite Actions

    func dislike() {
        guard currentIndex >= 0, currentIndex < images.count else { return }
        let image = images[currentIndex]
        store.addDislike(image.startdate)
        // Remove from favorites if present
        store.removeFavorite(image)
    }

    func undoDislike() async {
        guard currentIndex >= 0, currentIndex < images.count else { return }
        store.removeDislike(images[currentIndex].startdate)
        do { try await applyWallpaper(at: currentIndex) }
        catch { errorMessage = error.localizedDescription }
    }

    func toggleFavorite() {
        guard currentIndex >= 0, currentIndex < images.count else { return }
        let image = images[currentIndex]
        if store.isFavorited(image.startdate) {
            store.removeFavorite(image)
        } else {
            store.addFavorite(image)
            // Remove dislike if adding to favorites
            store.removeDislike(image.startdate)
        }
    }

    func applyFavorite(_ image: BingImage) async {
        isLoading = true
        errorMessage = nil
        do {
            let localURL = try await downloadImage(image)
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(localURL, for: screen)
            }
            currentTitle = image.title
            currentCopyright = image.copyright
            previewImage = NSImage(contentsOf: localURL)
            // If image is in our loaded list, update currentIndex
            if let idx = images.firstIndex(where: { $0.startdate == image.startdate }) {
                currentIndex = idx
            }
            showingFavorites = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func cachedImage(for image: BingImage) -> NSImage? {
        let localURL = cacheDir.appendingPathComponent("\(image.startdate)_\(locale)_UHD.jpg")
        return NSImage(contentsOf: localURL)
    }


    // MARK: - Wallpaper

    /// Download the image (if not cached) and set it as wallpaper on all screens
    func applyCurrentWallpaper() async {
        do { try await applyWallpaper(at: currentIndex) }
        catch { errorMessage = error.localizedDescription }
    }

    private func applyWallpaper(at index: Int) async throws {
        guard index >= 0, index < images.count else { return }
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

    /// Remove cached images older than 10 days, but keep favorites
    private func cleanOldCache() {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let favDates = store.favoriteDates()
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -10, to: Date()),
              let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let name = file.lastPathComponent
            let dateString = String(name.prefix(8))
            if favDates.contains(dateString) { continue }
            if let fileDate = formatter.date(from: dateString), fileDate < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
