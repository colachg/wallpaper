import ServiceManagement
import SwiftUI

@main
struct WallpaperApp: App {
    @State private var manager = WallpaperManager()
    @State private var updateChecker = UpdateChecker()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var refreshTrigger = 0
    @State private var isHoveringImage = false
    @State private var showCopied = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    init() {
        _manager.wrappedValue.start()
        _updateChecker.wrappedValue.start()
    }

    var body: some Scene {
        MenuBarExtra("Wallpaper", systemImage: "photo.on.rectangle") {
            VStack(spacing: 0) {
                imageCard
                Divider()
                toolbar
            }
            .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Image Card

    private var imageCard: some View {
        ZStack(alignment: .bottom) {
            if let image = manager.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if manager.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            // Title overlay
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                if let error = manager.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text(manager.currentTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Text(manager.currentCopyright)
                        .font(.caption2)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            )

            // Navigation arrows (visible on hover)
            HStack {
                navArrow("chevron.left", enabled: manager.hasPrevious) { Task { await manager.previous() } }
                Spacer()
                navArrow("chevron.right", enabled: manager.hasNext) { Task { await manager.next() } }
            }
            .padding(.horizontal, 6)
            .opacity(isHoveringImage ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHoveringImage)
        }
        .onHover { isHoveringImage = $0 }
        .onTapGesture { Task { await manager.applyCurrentWallpaper() } }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    private func navArrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial.opacity(0.8))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            if updateChecker.updateAvailable {
                switch updateChecker.updateState {
                case .idle:
                    Button { updateChecker.performUpdate() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .help("Update to v\(updateChecker.latestVersion ?? "")")

                case .downloading(let progress):
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .help("Downloading update... \(Int(progress * 100))%")

                case .installing:
                    ProgressView()
                        .controlSize(.small)
                        .help("Installing update...")

                case .failed:
                    Button { updateChecker.openReleasePage() } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .help("Update failed — click to open release page")
                }
            } else {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appVersion, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                } label: {
                    Image(systemName: showCopied ? "checkmark.circle" : "info.circle")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(showCopied ? "Copied!" : "Version \(appVersion)")
            }

            Spacer()

            Button {
                refreshTrigger += 1
                Task { await manager.refresh() }
                Task { await updateChecker.checkForUpdate() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, value: refreshTrigger)
            }
            .disabled(manager.isLoading)
            .help("Refresh")

            Spacer()

            Button {
                launchAtLogin.toggle()
                do {
                    if launchAtLogin { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch { launchAtLogin.toggle() }
            } label: {
                Image(systemName: launchAtLogin ? "checkmark.circle.fill" : "circle")
            }
            .help("Launch at Login")

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Quit")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
