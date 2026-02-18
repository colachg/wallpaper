import Foundation

struct BingResponse: Codable {
    let images: [BingImage]
}

struct BingImage: Codable {
    let startdate: String
    let url: String
    let urlbase: String
    let copyright: String
    let title: String
}

enum WallpaperError: LocalizedError {
    case invalidURL
    case noImages
    case downloadFailed
    case wallpaperSetFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noImages:
            return "No images found in Bing response"
        case .downloadFailed:
            return "Failed to download image"
        case .wallpaperSetFailed(let reason):
            return "Failed to set wallpaper: \(reason)"
        }
    }
}
