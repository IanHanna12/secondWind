#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

build="$root/.build/secondwind-debug"
export CLANG_MODULE_CACHE_PATH="$build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build/ModuleCache"

swift build --disable-sandbox --scratch-path "$build" --product SecondWind

app="$build/Debug/SecondWind.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$build/debug/SecondWind" "$app/Contents/MacOS/SecondWind"
cp "$root/Debug/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"

nohup "$app/Contents/MacOS/SecondWind" >"$build/SecondWind.log" 2>&1 &
print "Second Wind launched. Logs: $build/SecondWind.log"
