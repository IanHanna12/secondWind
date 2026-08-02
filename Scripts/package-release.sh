#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="1.0.0"
build_root="/private/tmp/secondwind-release-$version"
artifacts="$root/Artifacts"
release_root="$build_root/package/Second-Wind-$version"
app="$release_root/Second Wind.app"
archive="$artifacts/Second-Wind-$version.zip"
checksum="$artifacts/SHA256SUMS"

rm -rf "$build_root" "$archive" "$checksum"
mkdir -p "$artifacts" "$release_root"

cd "$root/Xcode"

xcodebuild \
    -project SecondWind.xcodeproj \
    -scheme App \
    -configuration Release \
    -derivedDataPath "$build_root" \
    CODE_SIGNING_ALLOWED=NO \
    build

ditto "$build_root/Build/Products/Release/SecondWind.app" "$app"

# The helper needs a Developer ID distribution setup. This release ships the
# standard app only; all storage, cleanup, Recovery, and history features work
# without it.
rm -rf "$app/Contents/Resources/SecondWindPrivilegedHelper"
rm -rf "$app/Contents/Library/LaunchDaemons"
rmdir "$app/Contents/Library" 2>/dev/null || true

# Ad-hoc signing makes the bundle internally consistent without implying that
# Gatekeeper can identify or trust its publisher. The release notes state that
# the ZIP is not notarized.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"

bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
bundle_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
bundle_revision=$(/usr/libexec/PlistBuddy -c 'Print :SecondWindSourceRevision' "$app/Contents/Info.plist")
bundle_date=$(/usr/libexec/PlistBuddy -c 'Print :SecondWindBuildDate' "$app/Contents/Info.plist")

[[ "$bundle_version" == "$version" ]] || {
    print -u2 "error: expected version $version, found $bundle_version"
    exit 1
}
[[ "$bundle_build" == "11" ]] || {
    print -u2 "error: expected build 11, found $bundle_build"
    exit 1
}
[[ "$bundle_executable" == "SecondWind" ]] || {
    print -u2 "error: expected executable SecondWind, found $bundle_executable"
    exit 1
}
[[ -n "$bundle_build" && -n "$bundle_revision" && -n "$bundle_date" ]] || {
    print -u2 "error: bundle build metadata is incomplete"
    exit 1
}
if [[ "$bundle_revision" == *-dirty && "${SECONDWIND_ALLOW_DIRTY_RELEASE:-0}" != "1" ]]; then
    print -u2 "error: refusing to package a dirty source revision"
    print -u2 "Set SECONDWIND_ALLOW_DIRTY_RELEASE=1 only for a local packaging smoke test."
    exit 1
fi
[[ -x "$app/Contents/MacOS/$bundle_executable" ]] || {
    print -u2 "error: app executable is missing"
    exit 1
}
[[ -f "$app/Contents/Info.plist" && -f "$app/Contents/PkgInfo" ]] || {
    print -u2 "error: required app resources are missing"
    exit 1
}
[[ ! -e "$app/Contents/Resources/SecondWindPrivilegedHelper" ]] || {
    print -u2 "error: the optional helper must not be included in the standard release"
    exit 1
}
[[ ! -e "$app/Contents/Library/LaunchDaemons" ]] || {
    print -u2 "error: the optional helper launch daemon must not be included in the standard release"
    exit 1
}
if find "$app" \( -name '.DS_Store' -o -name '*.dSYM' -o -name '*.xcuserstate' \) -print -quit | grep -q .; then
    print -u2 "error: release contains debug or user-specific data"
    exit 1
fi

for required_file in \
    "$root/LICENSE" \
    "$root/Docs/INSTALLATION.md" \
    "$root/Docs/RELEASE_NOTES_1.0.0.md" \
    "$root/observability/README.md" \
    "$root/docker/compose.yml"; do
    [[ -f "$required_file" ]] || {
        print -u2 "error: required release resource is missing: $required_file"
        exit 1
    }
done

cp "$root/LICENSE" "$release_root/LICENSE"
cp "$root/Docs/INSTALLATION.md" "$release_root/INSTALLATION.md"
cp "$root/Docs/RELEASE_NOTES_1.0.0.md" "$release_root/RELEASE_NOTES.md"

ditto -c -k --keepParent --norsrc "$release_root" "$archive"
if unzip -Z1 "$archive" | grep -E '(^|/)(\._|\.DS_Store|__MACOSX/)' -q; then
    print -u2 "error: release archive contains macOS metadata files"
    exit 1
fi
(cd "$artifacts" && shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")")

print "Release archive: $archive"
print "SHA-256: $checksum"
print "Bundle metadata: version $bundle_version ($bundle_build), revision $bundle_revision, built $bundle_date"
