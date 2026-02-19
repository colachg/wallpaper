app_name := "Wallpaper"
bundle_dir := "build/" + app_name + ".app"

# Build release binary
build:
    swift build -c release

# Generate app icon (Resources/AppIcon.icns)
icon:
    swift Scripts/generate-icon.swift

# Create .app bundle from release build
bundle: build icon
    rm -rf {{bundle_dir}}
    mkdir -p {{bundle_dir}}/Contents/MacOS
    mkdir -p {{bundle_dir}}/Contents/Resources
    cp .build/release/{{app_name}} {{bundle_dir}}/Contents/MacOS/{{app_name}}
    cp Resources/Info.plist {{bundle_dir}}/Contents/
    cp Resources/AppIcon.icns {{bundle_dir}}/Contents/Resources/
    codesign --force --sign - {{bundle_dir}}

# Debug build + run raw executable (fast iteration)
dev:
    swift build
    .build/debug/{{app_name}}

# Build bundle + open it (full test)
run: bundle
    open {{bundle_dir}}

# Install to /Applications
install: bundle
    rm -rf /Applications/{{app_name}}.app
    cp -R {{bundle_dir}} /Applications/{{app_name}}.app

# Remove build artifacts
clean:
    rm -rf .build build
