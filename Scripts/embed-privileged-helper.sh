#!/bin/zsh
set -euo pipefail

# This runs as an Xcode build phase only. It changes the build product, never
# the installed system: registration remains an explicit in-app user action.
helper="$BUILT_PRODUCTS_DIR/SecondWindPrivilegedHelper"
app="$TARGET_BUILD_DIR/$WRAPPER_NAME"
destination="$app/Contents/Resources/SecondWindPrivilegedHelper"
plist_source="$SRCROOT/LaunchDaemons/org.secondwind.PrivilegedMaintenanceHelper.plist"
plist_destination="$app/Contents/Library/LaunchDaemons/org.secondwind.PrivilegedMaintenanceHelper.plist"
app_info="$app/Contents/Info.plist"
source_root="$SRCROOT/.."

if [[ ! -x "$helper" ]]; then
  echo "error: SecondWindPrivilegedHelper was not built."
  exit 1
fi

if [[ ! -f "$plist_source" ]]; then
  echo "error: Privileged helper launch daemon plist is missing."
  exit 1
fi

/usr/bin/install -d "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons"
/usr/bin/ditto "$helper" "$destination"
/usr/bin/install -m 644 "$plist_source" "$plist_destination"

# This identifies the exact source used for this local build. It is deliberately
# not a release version: the app has no release cadence or update service.
revision=$(/usr/bin/git -C "$source_root" rev-parse --short HEAD 2>/dev/null || true)
revision=${revision:-unavailable}
if [[ "$revision" != "unavailable" ]] && [[ -n $(/usr/bin/git -C "$source_root" status --porcelain --untracked-files=normal) ]]; then
  revision="${revision}-dirty"
fi
build_date=$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")
/usr/libexec/PlistBuddy -c "Set :SecondWindSourceRevision $revision" "$app_info"
/usr/libexec/PlistBuddy -c "Set :SecondWindBuildDate $build_date" "$app_info"
