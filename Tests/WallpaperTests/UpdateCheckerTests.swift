import Foundation
import Testing

@testable import Wallpaper

@Suite("Semver Comparison")
struct SemverTests {
    @Test("newer major version")
    func newerMajor() {
        #expect(UpdateChecker.isNewer(remote: "2.0.0", than: "1.0.0"))
    }

    @Test("newer minor version")
    func newerMinor() {
        #expect(UpdateChecker.isNewer(remote: "1.1.0", than: "1.0.0"))
    }

    @Test("newer patch version")
    func newerPatch() {
        #expect(UpdateChecker.isNewer(remote: "1.0.1", than: "1.0.0"))
    }

    @Test("same version is not newer")
    func sameVersion() {
        #expect(!UpdateChecker.isNewer(remote: "1.0.0", than: "1.0.0"))
    }

    @Test("older version is not newer")
    func olderVersion() {
        #expect(!UpdateChecker.isNewer(remote: "0.9.0", than: "1.0.0"))
    }

    @Test("missing patch component treated as zero")
    func missingPatch() {
        #expect(UpdateChecker.isNewer(remote: "1.1", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer(remote: "1.0", than: "1.0.0"))
    }

    @Test("different length versions")
    func differentLengths() {
        #expect(UpdateChecker.isNewer(remote: "1.0.0.1", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer(remote: "1.0.0", than: "1.0.0.1"))
    }
}

@Suite("GitHub Release Decoding")
struct GitHubReleaseDecodingTests {
    @Test("decodes release with assets")
    func decodesRelease() throws {
        let json = """
            {
                "tag_name": "v1.2.3",
                "html_url": "https://github.com/colachg/wallpaper/releases/tag/v1.2.3",
                "assets": [
                    {
                        "name": "Wallpaper.app.zip",
                        "browser_download_url": "https://github.com/colachg/wallpaper/releases/download/v1.2.3/Wallpaper.app.zip"
                    }
                ]
            }
            """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))

        #expect(release.tag_name == "v1.2.3")
        #expect(release.html_url == "https://github.com/colachg/wallpaper/releases/tag/v1.2.3")
        #expect(release.assets.count == 1)
        #expect(release.assets[0].name == "Wallpaper.app.zip")
    }

    @Test("decodes release with empty assets")
    func emptyAssets() throws {
        let json = """
            {
                "tag_name": "v0.1.0",
                "html_url": "https://github.com/colachg/wallpaper/releases/tag/v0.1.0",
                "assets": []
            }
            """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))

        #expect(release.assets.isEmpty)
    }
}
