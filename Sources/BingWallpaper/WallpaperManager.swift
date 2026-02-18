import AppKit
import Combine
import Foundation

class WallpaperManager: ObservableObject {
    @Published var currentTitle: String = ""
    @Published var currentCopyright: String = ""
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private var timer: Timer?
    private let apiURL = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"

    private var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("BingWallpaper")
    }

    func start() {
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    @MainActor
    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            let image = try await fetchBingImageMetadata()
            let localURL = try await downloadImage(image)
            try setWallpaper(from: localURL)

            currentTitle = image.title
            currentCopyright = image.copyright
            lastUpdated = Date()
            cleanOldCache()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchBingImageMetadata() async throws -> BingImage {
        guard let url = URL(string: apiURL) else {
            throw WallpaperError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(BingResponse.self, from: data)

        guard let image = response.images.first else {
            throw WallpaperError.noImages
        }

        return image
    }

    private func downloadImage(_ image: BingImage) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let filename = "\(image.startdate)_UHD.jpg"
        let localURL = cacheDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        let imageURLString = "https://www.bing.com\(image.urlbase)_UHD.jpg"
        guard let imageURL = URL(string: imageURLString) else {
            throw WallpaperError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: imageURL)

        guard !data.isEmpty else {
            throw WallpaperError.downloadFailed
        }

        try data.write(to: localURL)
        return localURL
    }

    private func setWallpaper(from url: URL) throws {
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
            } catch {
                throw WallpaperError.wallpaperSetFailed(error.localizedDescription)
            }
        }
    }

    private func cleanOldCache() {
        let fileManager = FileManager.default
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)

        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files {
            guard let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                  let created = attrs[.creationDate] as? Date,
                  created < sevenDaysAgo
            else { continue }

            try? fileManager.removeItem(at: file)
        }
    }
}
