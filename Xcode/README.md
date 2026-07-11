# Release packaging shell

This directory is the direct-distribution Xcode shell. Open
`SecondWind.xcworkspace` in Xcode. The generated project is checked in;
after changing `project.yml`, regenerate it with
`xcodegen generate --spec project.yml` from this directory.

Set your Xcode Personal Team for a local development test, or a stable
Developer Team before distribution. The default app scheme is helper-free.
`ExperimentalPrivilegedHelper` builds the isolated helper target only; it does
not embed or register it in the app.

The default app uses hardened runtime and intentionally has no App Store
sandbox target.

The experimental helper accepts only JSON-encoded `PrivilegedMaintenanceRequest`
values. It is not part of the current app product.
