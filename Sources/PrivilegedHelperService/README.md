# Second Wind privileged helper target

This module is deliberately excluded from the default SwiftPM source build.
Second Wind works without it there. The Xcode **App** scheme builds and embeds
this helper in the app bundle.

The helper is not registered or invoked until the user explicitly enables it
from the app and approves it in System Settings.

## Local test path

1. Open `Xcode/SecondWind.xcworkspace` and set your Xcode Personal Team (or
   development team) on both targets.
2. Build and run the **App** scheme, not `Scripts/run-debug-app.sh`.
3. In System tasks, choose **Enable privileged helper**, approve it in System
   Settings, then return to the app and refresh its status.

Developer ID and notarization are needed for public prebuilt distribution, not
for a locally development-signed test build.

## Security boundary

- The app sends either a `MaintenanceTask` enum plus an optional local-volume
  UUID, or a typed request for one verified app bundle directly inside
  `/Applications`. No command, shell text, or arbitrary path crosses XPC.
- The helper resolves the UUID against currently mounted local volumes before
  it maps a task to fixed system executable paths.
- For an administrator-owned app, the helper verifies its path, bundle type,
  bundle identifier, and the connecting process owner. It moves only that app
  into the caller's Finder Trash without changing its ownership or metadata.
- Service Management enforces `SMAuthorizedClients`; the helper also verifies
  the connecting process's code signature, identifier, and development-team
  identity before exporting its XPC object.
- The launch daemon has neither `RunAtLoad` nor `KeepAlive`: it starts only to
  service an approved request.

The default source-only workflow uses `Scripts/run-debug-app.sh`; it does not
bundle, register, install, or require this module.
