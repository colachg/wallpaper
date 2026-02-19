import Foundation

/// Bing HPImageArchive JSON response
struct BingResponse: Codable {
    let images: [BingImage]
}

/// A single Bing daily wallpaper entry
struct BingImage: Codable {
    let startdate: String  // e.g. "20260218"
    let urlbase: String    // path to build UHD image URL
    let copyright: String
    let title: String
}

enum WallpaperError: LocalizedError {
    case noImages
    case downloadFailed
    case setFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImages: return "No images found"
        case .downloadFailed: return "Failed to download image"
        case .setFailed(let reason): return "Failed to set wallpaper: \(reason)"
        }
    }
}
