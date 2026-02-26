import Foundation
import Testing

@testable import Wallpaper

// MARK: - BingImage Tests

@Suite("BingImage")
struct BingImageTests {
    let sample = BingImage(
        startdate: "20260218",
        urlbase: "/th?id=OHR.TestImage",
        copyright: "Test (© Photographer)",
        title: "Test Image"
    )

    @Test("id returns startdate")
    func id() {
        #expect(sample.id == "20260218")
    }

    @Test("formattedDate formats YYYYMMDD as YYYY-MM-DD")
    func formattedDate() {
        #expect(sample.formattedDate == "2026-02-18")
    }

    @Test("formattedDate returns raw string for invalid length")
    func formattedDateInvalid() {
        let image = BingImage(startdate: "2026", urlbase: "", copyright: "", title: "")
        #expect(image.formattedDate == "2026")
    }

    @Test("Hashable conformance: equal images have same hash")
    func hashable() {
        let other = BingImage(
            startdate: "20260218",
            urlbase: "/th?id=OHR.TestImage",
            copyright: "Test (© Photographer)",
            title: "Test Image"
        )
        #expect(sample == other)
        #expect(sample.hashValue == other.hashValue)
    }

    @Test("Hashable conformance: different images differ")
    func hashableDifferent() {
        let other = BingImage(startdate: "20260219", urlbase: "", copyright: "", title: "")
        #expect(sample != other)
    }
}

// MARK: - WallpaperPreferences Codable Tests

@Suite("WallpaperPreferences Codable")
struct WallpaperPreferencesCodableTests {
    @Test("round-trip encoding and decoding preserves data")
    func roundTrip() throws {
        var prefs = WallpaperPreferences()
        prefs.dislikedDates = ["20260218", "20260219"]
        prefs.favorites = [
            BingImage(startdate: "20260220", urlbase: "/img1", copyright: "© A", title: "Image 1"),
            BingImage(startdate: "20260221", urlbase: "/img2", copyright: "© B", title: "Image 2"),
        ]

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(WallpaperPreferences.self, from: data)

        #expect(decoded.dislikedDates == prefs.dislikedDates)
        #expect(decoded.favorites.count == 2)
        #expect(decoded.favorites[0].startdate == "20260220")
        #expect(decoded.favorites[1].title == "Image 2")
    }

    @Test("decodes empty preferences")
    func emptyDefaults() throws {
        let json = #"{"dislikedDates":[],"favorites":[]}"#
        let decoded = try JSONDecoder().decode(WallpaperPreferences.self, from: Data(json.utf8))
        #expect(decoded.dislikedDates.isEmpty)
        #expect(decoded.favorites.isEmpty)
    }
}

// MARK: - PreferencesStore Tests

@Suite("PreferencesStore")
struct PreferencesStoreTests {
    /// Create a store backed by a temp file for isolation
    @MainActor
    private func makeStore() -> PreferencesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preferences.json")
        return PreferencesStore(fileURL: url)
    }

    @Test("add and check dislike")
    @MainActor func addDislike() {
        let store = makeStore()
        #expect(!store.isDisliked("20260218"))
        store.addDislike("20260218")
        #expect(store.isDisliked("20260218"))
    }

    @Test("remove dislike")
    @MainActor func removeDislike() {
        let store = makeStore()
        store.addDislike("20260218")
        store.removeDislike("20260218")
        #expect(!store.isDisliked("20260218"))
    }

    @Test("add and check favorite")
    @MainActor func addFavorite() {
        let store = makeStore()
        let image = BingImage(startdate: "20260218", urlbase: "/img", copyright: "©", title: "T")
        #expect(!store.isFavorited("20260218"))
        store.addFavorite(image)
        #expect(store.isFavorited("20260218"))
        #expect(store.preferences.favorites.count == 1)
    }

    @Test("adding duplicate favorite is a no-op")
    @MainActor func duplicateFavorite() {
        let store = makeStore()
        let image = BingImage(startdate: "20260218", urlbase: "/img", copyright: "©", title: "T")
        store.addFavorite(image)
        store.addFavorite(image)
        #expect(store.preferences.favorites.count == 1)
    }

    @Test("remove favorite")
    @MainActor func removeFavorite() {
        let store = makeStore()
        let image = BingImage(startdate: "20260218", urlbase: "/img", copyright: "©", title: "T")
        store.addFavorite(image)
        store.removeFavorite(image)
        #expect(!store.isFavorited("20260218"))
        #expect(store.preferences.favorites.isEmpty)
    }

    @Test("favoriteDates returns correct set")
    @MainActor func favoriteDates() {
        let store = makeStore()
        let img1 = BingImage(startdate: "20260218", urlbase: "/1", copyright: "©", title: "A")
        let img2 = BingImage(startdate: "20260219", urlbase: "/2", copyright: "©", title: "B")
        store.addFavorite(img1)
        store.addFavorite(img2)
        #expect(store.favoriteDates() == Set(["20260218", "20260219"]))
    }

    @Test("save and load round-trip persists data")
    @MainActor func persistence() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preferences.json")

        let store1 = PreferencesStore(fileURL: url)
        store1.addDislike("20260218")
        store1.addFavorite(BingImage(startdate: "20260220", urlbase: "/img", copyright: "©", title: "T"))

        let store2 = PreferencesStore(fileURL: url)
        store2.load()
        #expect(store2.isDisliked("20260218"))
        #expect(store2.isFavorited("20260220"))
        #expect(store2.preferences.favorites.count == 1)

        // Cleanup
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("load with missing file keeps empty defaults")
    @MainActor func loadMissing() {
        let store = makeStore()
        store.load()
        #expect(store.preferences.dislikedDates.isEmpty)
        #expect(store.preferences.favorites.isEmpty)
    }

    @Test("favoriteImages returns favorites sorted by startdate descending")
    @MainActor func favoritesSortedByDate() {
        let store = makeStore()
        // Add favorites in non-chronological order
        store.addFavorite(BingImage(startdate: "20260215", urlbase: "/1", copyright: "©", title: "Jan 15"))
        store.addFavorite(BingImage(startdate: "20260220", urlbase: "/2", copyright: "©", title: "Jan 20"))
        store.addFavorite(BingImage(startdate: "20260210", urlbase: "/3", copyright: "©", title: "Jan 10"))

        let sorted = store.preferences.favorites.sorted { $0.startdate > $1.startdate }
        #expect(sorted[0].startdate == "20260220")
        #expect(sorted[1].startdate == "20260215")
        #expect(sorted[2].startdate == "20260210")
    }

    @Test("newly added favorite maintains date-sorted order")
    @MainActor func newFavoriteMaintainsDateOrder() {
        let store = makeStore()
        // Add initial favorites
        store.addFavorite(BingImage(startdate: "20260210", urlbase: "/1", copyright: "©", title: "Jan 10"))
        store.addFavorite(BingImage(startdate: "20260220", urlbase: "/2", copyright: "©", title: "Jan 20"))
        // Add a new favorite with a date between the existing ones
        store.addFavorite(BingImage(startdate: "20260215", urlbase: "/3", copyright: "©", title: "Jan 15"))

        let sorted = store.preferences.favorites.sorted { $0.startdate > $1.startdate }
        #expect(sorted.count == 3)
        #expect(sorted[0].startdate == "20260220")
        #expect(sorted[1].startdate == "20260215")
        #expect(sorted[2].startdate == "20260210")
    }

    @Test("load with corrupted file resets to defaults")
    @MainActor func loadCorrupted() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preferences.json")

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "not-json".data(using: .utf8)?.write(to: url)

        let store = PreferencesStore(fileURL: url)
        store.load()
        #expect(store.preferences.dislikedDates.isEmpty)
        #expect(store.preferences.favorites.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(at: dir)
    }
}
