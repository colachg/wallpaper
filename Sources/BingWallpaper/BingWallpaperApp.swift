import ServiceManagement
import SwiftUI

@main
struct BingWallpaperApp: App {
    @StateObject private var manager: WallpaperManager

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        let m = WallpaperManager()
        _manager = StateObject(wrappedValue: m)
        m.start()
    }

    var body: some Scene {
        MenuBarExtra("Bing Wallpaper", systemImage: "photo.on.rectangle") {
            if manager.isLoading {
                Text("Updating wallpaper...")
            } else if let error = manager.errorMessage {
                Text("Error: \(error)")
            } else if !manager.currentTitle.isEmpty {
                Text(manager.currentTitle)
                Text(manager.currentCopyright)
                    .font(.caption)
            }

            if let date = manager.lastUpdated {
                Divider()
                Text("Updated: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
            }

            Divider()

            Button("Refresh Now") {
                Task { await manager.refresh() }
            }
            .keyboardShortcut("r")

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
