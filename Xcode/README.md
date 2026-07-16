# Release packaging shell

This directory is the direct-distribution Xcode shell. Open
`SecondWind.xcworkspace` in Xcode. The generated project is checked in;
after changing `project.yml`, regenerate it with
`xcodegen generate --spec project.yml` from this directory.

Set your Xcode Personal Team for a local development test, or a stable
Developer Team before distribution. The **App** scheme builds the optional
helper target and embeds it in the app bundle. It does not register or run the
helper: the user enables it from the app and approves it in System Settings.
`ExperimentalPrivilegedHelper` remains available to build the helper target in
isolation.

The default app uses hardened runtime and intentionally has no App Store
sandbox target.

The optional helper accepts only JSON-encoded `PrivilegedMaintenanceRequest`
values. It is bundled only by an Xcode App build, never by the SwiftPM launcher.
