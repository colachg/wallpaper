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

    /// The image last written to the desktop, and the one that was there before the
    /// favorites panel was opened, so browsing favorites can be undone.
    private var desktopImage: BingImage?
    private var preFavoritesDesktopImage: BingImage?

    private let store = PreferencesStore.shared

    private static let maxImages = 10

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

    /// Newest-first; the store keeps this sorted so the view can read it every render pass
    var favoriteImages: [BingImage] { store.sortedFavorites }

    var currentFavorite: BingImage? {
        let favs = favoriteImages
        guard favoriteIndex >= 0, favoriteIndex < favs.count else { return nil }
        return favs[favoriteIndex]
    }

    var hasPreviousFavorite: Bool { favoriteIndex < favoriteImages.count - 1 }
    var hasNextFavorite: Bool { favoriteIndex > 0 }

    func showFavorites() async {
        showingFavorites = true
        favoriteIndex = 0
        preFavoritesDesktopImage = desktopImage
        await applyFavoriteAtIndex()
    }

    func hideFavorites() async {
        showingFavorites = false
        favoritePreviewImage = nil
        await restoreDesktopAfterFavorites()
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
            favoritePreviewImage = nil
            await restoreDesktopAfterFavorites()
        } else {
            favoriteIndex = min(favoriteIndex, favoriteImages.count - 1)
            await applyFavoriteAtIndex()
        }
    }

    /// Put back the wallpaper that was on the desktop before favorites were browsed.
    /// Falls back to the most recent non-disliked image if that one is gone or now disliked.
    private func restoreDesktopAfterFavorites() async {
        let saved = preFavoritesDesktopImage
        preFavoritesDesktopImage = nil

        do {
            if let saved, !store.isDisliked(saved.startdate) {
                // Preview state already describes currentIndex, so only the desktop needs fixing
                try await setDesktop(saved)
            } else if let idx = images.firstIndex(where: { !store.isDisliked($0.startdate) }) {
                currentIndex = idx
                try await applyWallpaper(at: idx)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Download favorite at current index (if needed), apply to all screens, update preview
    private func applyFavoriteAtIndex() async {
        guard let fav = currentFavorite else {
            favoritePreviewImage = nil
            return
        }
        do {
            let localURL = try await setDesktop(fav)
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
        defer { isLoading = false }
        errorMessage = nil
        do {
            var allImages: [BingImage] = []
            for idx in stride(from: 0, to: Self.maxImages, by: 5) {
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
    }

    /// Refresh: check for the latest image only, insert if new, then apply it
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            guard let latest = try await fetchImages(idx: 0, count: 1).first else { return }

            // Only accept a strictly newer date — an older entry at the head would break
            // the descending order that navigation and "first non-disliked" rely on.
            let isNewer = images.first.map { latest.startdate > $0.startdate } ?? true
            if isNewer {
                images.insert(latest, at: 0)
                // Every existing entry shifted down by one, so currentIndex must follow
                currentIndex += 1
                if images.count > Self.maxImages {
                    images.removeLast(images.count - Self.maxImages)
                }
                currentIndex = min(currentIndex, images.count - 1)
                cleanOldCache()
            }

            // Don't yank the desktop out from under the favorites panel, and never
            // auto-apply a disliked wallpaper
            guard !showingFavorites, !store.isDisliked(latest.startdate),
                let idx = images.firstIndex(where: { $0.startdate == latest.startdate })
            else { return }
            currentIndex = idx
            try await applyWallpaper(at: idx)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch images from Bing API, bypassing HTTP cache
    private func fetchImages(idx: Int, count: Int) async throws -> [BingImage] {
        var components = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: String(idx)),
            URLQueryItem(name: "n", value: String(count)),
            URLQueryItem(name: "mkt", value: locale),
        ]
        guard let url = components?.url else { throw WallpaperError.invalidURL }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BingResponse.self, from: data).images
    }

    // MARK: - Navigation

    func previous() async {
        guard !isLoading, hasPrevious else { return }
        isLoading = true
        defer { isLoading = false }
        currentIndex += 1
        await showOrApply(at: currentIndex)
    }

    func next() async {
        guard !isLoading, hasNext else { return }
        isLoading = true
        defer { isLoading = false }
        currentIndex -= 1
        await showOrApply(at: currentIndex)
    }

    /// Preview-only if disliked, otherwise apply as wallpaper
    private func showOrApply(at index: Int) async {
        guard index >= 0, index < images.count else { return }
        let image = images[index]
        do {
            if store.isDisliked(image.startdate) {
                try await previewOnly(at: index)
            } else {
                try await applyWallpaper(at: index)
            }
        } catch {
            errorMessage = error.localizedDescription
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let localURL = try await setDesktop(image)
            currentTitle = image.title
            currentCopyright = image.copyright
            previewImage = NSImage(contentsOf: localURL)
            // If image is in our loaded list, update currentIndex
            if let idx = images.firstIndex(where: { $0.startdate == image.startdate }) {
                currentIndex = idx
            }
            // Deliberate choice — nothing to restore when the panel closes
            preFavoritesDesktopImage = nil
            favoritePreviewImage = nil
            showingFavorites = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cachedImage(for image: BingImage) -> NSImage? {
        NSImage(contentsOf: cacheDir.appendingPathComponent(cacheFileName(for: image)))
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
        let localURL = try await setDesktop(image)

        currentTitle = image.title
        currentCopyright = image.copyright
        previewImage = NSImage(contentsOf: localURL)
    }

    /// Download (if needed) and set the image on every screen. Leaves preview state alone.
    @discardableResult
    private func setDesktop(_ image: BingImage) async throws -> URL {
        let localURL = try await downloadImage(image)
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(localURL, for: screen)
        }
        desktopImage = image
        return localURL
    }

    /// Keyed by the image's own URL rather than the current locale, so a region change
    /// never orphans a cached favorite that was saved under a different market.
    private func cacheFileName(for image: BingImage) -> String {
        let token = String(image.urlbase.filter { $0.isLetter || $0.isNumber }.suffix(80))
        return "\(image.startdate)_\(token)_UHD.jpg"
    }

    /// Download UHD image to cache, skip if already exists
    private func downloadImage(_ image: BingImage) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent(cacheFileName(for: image))
        if FileManager.default.fileExists(atPath: localURL.path) { return localURL }

        guard let url = URL(string: "https://www.bing.com\(image.urlbase)_UHD.jpg") else {
            throw WallpaperError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !data.isEmpty else { throw WallpaperError.downloadFailed }

        try data.write(to: localURL)
        return localURL
    }

    // MARK: - Cache

    /// Remove cached images older than 10 days, but keep favorites
    private func cleanOldCache() {
        let fm = FileManager.default
        // Filenames are always Gregorian yyyyMMdd — never parse them with the user's calendar
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"

        let favDates = store.favoriteDates()
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.maxImages, to: Date()),
            let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
        else { return }
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
