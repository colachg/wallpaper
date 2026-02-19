import ServiceManagement
import SwiftUI

@main
struct WallpaperApp: App {
    @State private var manager = WallpaperManager()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var refreshRotation = 0.0
    @State private var isHoveringImage = false

    init() {
        _manager.wrappedValue.start()
    }

    var body: some Scene {
        MenuBarExtra("Wallpaper", systemImage: "photo.on.rectangle") {
            VStack(spacing: 0) {
                imageCard
                dotIndicators
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

    // MARK: - Dot Indicators

    @ViewBuilder
    private var dotIndicators: some View {
        if manager.images.count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<manager.images.count, id: \.self) { i in
                    Circle()
                        .fill(i == manager.images.count - 1 - manager.currentIndex ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                refreshRotation += 360
                Task { await manager.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(refreshRotation))
                    .animation(.linear(duration: 0.6), value: refreshRotation)
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
