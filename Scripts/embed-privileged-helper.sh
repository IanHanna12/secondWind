#!/bin/zsh
set -euo pipefail

# This runs as an Xcode build phase only. It changes the build product, never
# the installed system: registration remains an explicit in-app user action.
helper="$BUILT_PRODUCTS_DIR/SecondWindPrivilegedHelper"
app="$TARGET_BUILD_DIR/$WRAPPER_NAME"
destination="$app/Contents/Resources/SecondWindPrivilegedHelper"
plist_source="$SRCROOT/LaunchDaemons/org.secondwind.PrivilegedMaintenanceHelper.plist"
plist_destination="$app/Contents/Library/LaunchDaemons/org.secondwind.PrivilegedMaintenanceHelper.plist"

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
