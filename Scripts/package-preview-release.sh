#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.6.0"
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

bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
bundle_revision=$(/usr/libexec/PlistBuddy -c 'Print :SecondWindSourceRevision' "$app/Contents/Info.plist")
bundle_date=$(/usr/libexec/PlistBuddy -c 'Print :SecondWindBuildDate' "$app/Contents/Info.plist")

[[ "$bundle_version" == "$version" ]] || {
    print -u2 "error: expected version $version, found $bundle_version"
    exit 1
}
[[ -n "$bundle_build" && -n "$bundle_revision" && -n "$bundle_date" ]] || {
    print -u2 "error: bundle build metadata is incomplete"
    exit 1
}
[[ -x "$app/Contents/MacOS/SecondWind" ]] || {
    print -u2 "error: app executable is missing"
    exit 1
}
[[ -f "$app/Contents/Info.plist" && -f "$app/Contents/PkgInfo" ]] || {
    print -u2 "error: required app resources are missing"
    exit 1
}
[[ ! -e "$app/Contents/Resources/SecondWindPrivilegedHelper" ]] || {
    print -u2 "error: the optional helper must not be included in this preview"
    exit 1
}
[[ ! -e "$app/Contents/Library/LaunchDaemons" ]] || {
    print -u2 "error: the optional helper launch daemon must not be included in this preview"
    exit 1
}
if find "$app" \( -name '.DS_Store' -o -name '*.dSYM' -o -name '*.xcuserstate' \) -print -quit | grep -q .; then
    print -u2 "error: preview contains debug or user-specific data"
    exit 1
fi

ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive" > "$checksum"

print "Preview archive: $archive"
print "SHA-256: $checksum"
print "Bundle metadata: version $bundle_version ($bundle_build), revision $bundle_revision, built $bundle_date"
