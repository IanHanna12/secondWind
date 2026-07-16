# Second Wind

> Give your Mac room to breathe.

Second Wind is an offline-first macOS 15+ app for reviewing known cleanup
candidates and making deliberate storage changes. It is independently
implemented and has no telemetry, analytics, cloud sync, remote rule downloads,
or update checks.

> **Early development** — Second Wind is an early proof of concept. Its core
> cleanup, audit, and Recovery flows are implemented, but interfaces, rules,
> and stored formats may change incompatibly while the project develops.
> The current public development version is **0.1.0**.

Second Wind is intentionally conservative. It only acts on locations it
explicitly understands. Unknown or ambiguous data is left untouched rather
than guessed at.

> **Latest update · 16 July 2026** Rules can now be managed in-app through
> approved safe routes, and direct Trash actions accept only validated scan
> findings. Read the [update history](UPDATES.md).

Read the project's [philosophy](PHILOSOPHY.md) for the principles behind those
choices.

## Quick start

Second Wind requires macOS 15 or later and Xcode or the Xcode Command Line
Tools.

```bash
git clone https://github.com/IanHanna12/secondWind.git
cd secondWind
./Scripts/run-debug-app.sh
```

This launches the standard app without the optional privileged helper enabled.

## What it helps with

- Review storage that Second Wind knows how to handle.
- Move reviewed items to Finder Trash or keep them in local Recovery storage.
- Track changes in the storage areas it understands.
- Inspect installed apps and their exact, known support paths.
- Check a validated local volume with macOS's read-only verification.

## Guarantees and limits

- Everything stays on your Mac. No account or network service is required.
- All changes are reviewed and explicitly confirmed before execution. Nothing
  is deleted automatically.
- Recovery items remain locally recoverable until you decide otherwise.
- Ambiguous or sensitive locations stay protected rather than being guessed at.
- It does not promise to speed up your Mac, clean RAM, or invent
  system-health scores.

## Optional privileged helper

The standard app does not need a privileged helper. The Xcode **App** scheme
can build one for rebuilding this Mac's startup-volume Spotlight index, running
fixed periodic scripts on macOS versions that still provide them, and moving a
verified administrator-owned app from `/Applications` into the current user's
Trash. It remains inactive until the user enables it in System tasks and
approves it in System Settings. It accepts neither command text nor arbitrary
paths.

To test it locally, open `Xcode/SecondWind.xcworkspace`, select the same
signing team for both targets, build the **App** scheme, then enable the helper
from System tasks. See the [helper notes](Optional/SecondWindPrivilegedHelper/README.md)
for its boundary and local test path.

## Development

```bash
swift build --disable-sandbox --scratch-path .build/secondwind-debug
swift test --disable-sandbox --scratch-path .build/secondwind-debug
```

For the GUI app, use:

```bash
./Scripts/run-debug-app.sh
```

## Xcode app build and packaging

The [Xcode](Xcode/README.md) directory contains the checked-in Xcode project,
the App scheme, and the optional helper target. It also documents the path for
local signing and later direct distribution.
