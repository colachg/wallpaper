# Wallpaper

A lightweight macOS menu bar app that sets your desktop wallpaper to the Bing daily image.

## Features

- Browse the last 16 days of Bing wallpapers with navigation arrows
- UHD image quality on all connected displays
- Locale-aware — fetches wallpapers for your system language
- Hourly auto-refresh
- Launch at login
- Local image caching with automatic cleanup
- No external dependencies — pure Swift + Apple frameworks

## Requirements

- macOS 15 (Sequoia) or later
- Swift 6.2+
- [just](https://github.com/casey/just) (task runner)

## Build & Install

```sh
# Debug build + run (fast iteration)
just dev

# Release build + open as .app bundle
just run

# Install to /Applications
just install
```

## License

MIT
