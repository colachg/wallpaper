# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu bar app that fetches and sets Bing daily wallpapers. Pure Swift, no external dependencies — uses only Apple frameworks (SwiftUI, AppKit, ServiceManagement, Foundation).

Requires Swift 6.2+ and macOS 15+.

## Build & Run Commands

```sh
just dev       # Debug build + run executable directly (fast iteration)
just run       # Release build → create .app bundle → open in Finder
just build     # Release build only
just bundle    # Build + create signed .app bundle in build/
just install   # Install to /Applications/Wallpaper.app
just clean     # Remove .build/ and build/ directories
```

There are no tests or linting configured.

## Architecture

Three-file MVVM structure:

- **WallpaperApp.swift** — `@main` SwiftUI app entry point. Menu bar window UI with image preview card, navigation arrows, dot indicators, and toolbar (refresh, launch-at-login, quit).
- **WallpaperManager.swift** — `@MainActor @Observable` view model. Handles Bing API fetching (last 16 days via two paginated calls), UHD image downloading, file-based caching (`~/Library/Caches/BingWallpaper/`), wallpaper application to all screens, and hourly refresh timer.
- **BingAPI.swift** — Codable models (`BingResponse`, `BingImage`) and `WallpaperError` enum.

API endpoint: `https://www.bing.com/HPImageArchive.aspx?format=js&idx={idx}&n={count}&mkt={locale}`

## Bundle Configuration

- Bundle ID: `com.colachg.Wallpaper`
- `LSUIElement: true` (menu bar only, no dock icon)
- Info.plist lives in `Resources/` and is copied into the bundle by `just bundle`
