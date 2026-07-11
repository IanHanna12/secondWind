# Second Wind privileged helper target

This module is deliberately excluded from the default SwiftPM source build.
Second Wind works without it.

The `ExperimentalPrivilegedHelper` Xcode scheme builds this target in
isolation. It is not embedded, registered, or invoked by the current app.

## Local test path

1. Set your Xcode Personal Team (or development team) on both targets.
2. Build the `ExperimentalPrivilegedHelper` scheme, not `Scripts/run-debug-app.sh`.
3. Do not register it against the current app; the product integration is
   intentionally disabled until it has a justified root-only feature.

Developer ID and notarization are needed for public prebuilt distribution, not
for a locally development-signed test build.

## Security boundary

- The app sends only a `MaintenanceTask` enum plus an optional local-volume
  UUID. No command, shell text, or path crosses XPC.
- The helper resolves the UUID against currently mounted local volumes before
  it maps a task to fixed system executable paths.
- Service Management enforces `SMAuthorizedClients`; the helper also verifies
  the connecting process's code signature, identifier, and development-team
  identity before exporting its XPC object.
- The launch daemon has neither `RunAtLoad` nor `KeepAlive`: it starts only to
  service an approved request.

The default source-only workflow uses `Scripts/run-debug-app.sh`; it does not
bundle, register, install, or require this module.
