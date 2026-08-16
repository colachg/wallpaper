import Foundation

struct WallpaperPreferences: Codable {
    var dislikedDates: Set<String> = []  // startdate strings, e.g. "20260218"
    var favorites: [BingImage] = []       // full metadata for re-download
}

@MainActor @Observable
final class PreferencesStore {
    static let shared = PreferencesStore()
    private(set) var preferences = WallpaperPreferences()
    /// Favorites in newest-first order, kept in sync on mutation so callers never re-sort
    private(set) var sortedFavorites: [BingImage] = []
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BingWallpaper")
            .appendingPathComponent("preferences.json")
    }

    func load() {
        let fm = FileManager.default
        defer { rebuildSortedFavorites() }
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            preferences = try JSONDecoder().decode(WallpaperPreferences.self, from: data)
        } catch {
            // Start fresh, but move the unreadable file aside first: otherwise the next
            // save() would overwrite it and destroy every favorite and dislike for good.
            let backupURL = fileURL.appendingPathExtension("corrupt")
            try? fm.removeItem(at: backupURL)
            try? fm.moveItem(at: fileURL, to: backupURL)
            preferences = WallpaperPreferences()
        }
    }

    func save() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(preferences)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent failure — preferences are non-critical
        }
    }

    // MARK: - Dislikes

    func addDislike(_ date: String) {
        preferences.dislikedDates.insert(date)
        save()
    }

    func removeDislike(_ date: String) {
        preferences.dislikedDates.remove(date)
        save()
    }

    func isDisliked(_ date: String) -> Bool {
        preferences.dislikedDates.contains(date)
    }

    // MARK: - Favorites

    func addFavorite(_ image: BingImage) {
        guard !preferences.favorites.contains(where: { $0.startdate == image.startdate }) else { return }
        preferences.favorites.append(image)
        rebuildSortedFavorites()
        save()
    }

    func removeFavorite(_ image: BingImage) {
        preferences.favorites.removeAll { $0.startdate == image.startdate }
        rebuildSortedFavorites()
        save()
    }

    func isFavorited(_ date: String) -> Bool {
        preferences.favorites.contains { $0.startdate == date }
    }

    func favoriteDates() -> Set<String> {
        Set(preferences.favorites.map(\.startdate))
    }

    private func rebuildSortedFavorites() {
        sortedFavorites = preferences.favorites.sorted { $0.startdate > $1.startdate }
    }
}
