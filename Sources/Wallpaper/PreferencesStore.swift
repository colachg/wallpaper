import Foundation

struct WallpaperPreferences: Codable {
    var dislikedDates: Set<String> = []  // startdate strings, e.g. "20260218"
    var favorites: [BingImage] = []       // full metadata for re-download
}

@MainActor @Observable
final class PreferencesStore {
    static let shared = PreferencesStore()
    private(set) var preferences = WallpaperPreferences()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BingWallpaper")
            .appendingPathComponent("preferences.json")
    }

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            preferences = try JSONDecoder().decode(WallpaperPreferences.self, from: data)
        } catch {
            // If corrupted, start fresh
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
        save()
    }

    func removeFavorite(_ image: BingImage) {
        preferences.favorites.removeAll { $0.startdate == image.startdate }
        save()
    }

    func isFavorited(_ date: String) -> Bool {
        preferences.favorites.contains { $0.startdate == date }
    }

    func favoriteDates() -> Set<String> {
        Set(preferences.favorites.map(\.startdate))
    }
}
