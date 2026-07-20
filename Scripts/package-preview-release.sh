#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.5.0"
build_root="/private/tmp/secondwind-preview-release-$version"
artifacts="$root/Artifacts"
app="$artifacts/SecondWind.app"
archive="$artifacts/SecondWind-$version-preview.zip"
checksum="$archive.sha256"

rm -rf "$build_root" "$app" "$archive" "$checksum"
mkdir -p "$artifacts"

cd "$root/Xcode"

xcodebuild \
    -workspace SecondWind.xcworkspace \
    -scheme App \
    -configuration Release \
    -derivedDataPath "$build_root" \
    CODE_SIGNING_ALLOWED=NO \
    build

ditto "$build_root/Build/Products/Release/SecondWind.app" "$app"

# The helper needs a Developer ID distribution setup. This preview ships the
# standard app only; all storage, cleanup, Recovery, and history features work
# without it.
rm -rf "$app/Contents/Resources/SecondWindPrivilegedHelper"
rm -rf "$app/Contents/Library/LaunchDaemons"
rmdir "$app/Contents/Library" 2>/dev/null || true

# Ad-hoc signing makes the bundle internally consistent without implying that
# Gatekeeper can identify or trust its publisher. The release notes state that
# the ZIP is not notarized.
codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive" > "$checksum"

print "Preview archive: $archive"
print "SHA-256: $checksum"
