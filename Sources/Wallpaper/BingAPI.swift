import Foundation

/// Bing HPImageArchive JSON response
struct BingResponse: Codable {
    let images: [BingImage]
}

/// A single Bing daily wallpaper entry
struct BingImage: Codable, Hashable, Identifiable {
    let startdate: String  // e.g. "20260218"
    let urlbase: String    // path to build UHD image URL
    let copyright: String
    let title: String

    var id: String { startdate }

    /// Formats "20260218" as "2026-02-18"
    var formattedDate: String {
        guard startdate.count == 8 else { return startdate }
        let y = startdate.prefix(4)
        let m = startdate.dropFirst(4).prefix(2)
        let d = startdate.dropFirst(6).prefix(2)
        return "\(y)-\(m)-\(d)"
    }
}

enum WallpaperError: LocalizedError {
    case noImages
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .noImages: return "No images found"
        case .downloadFailed: return "Failed to download image"
        }
    }
}
