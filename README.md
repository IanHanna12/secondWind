# Second Wind

> Give your Mac room to breathe.

Second Wind is an offline-first macOS 15+ app for reviewing known cleanup
candidates and making deliberate storage changes. It is independently
implemented and has no telemetry, analytics, cloud sync, remote rule downloads,
or update checks.

> **0.5.0 Preview** — Second Wind is an early, locally distributed preview.
> Its core cleanup, audit, Recovery, and storage-change flows are implemented,
> but interfaces, rules, and stored formats may still change incompatibly.
> Preview downloads are not notarized and macOS may require an explicit
> confirmation before opening them.

Second Wind is intentionally conservative. It only acts on locations it
explicitly understands. Unknown or ambiguous data is left untouched rather
than guessed at.

> **Latest update · 20 July 2026** The cleanup review now explains every
> suggestion's origin, regeneration, protection, and Recovery path. Storage
> intelligence makes changes between scans and local scan history visible.
> Read the [update history](UPDATES.md).

Read the project's [philosophy](PHILOSOPHY.md) for the principles behind those
choices.

## In the app

<p>
  <img src="Docs/Screenshots/home-storage-overview.png" alt="Second Wind home storage overview" width="49%">
  <img src="Docs/Screenshots/cleanup-selection.png" alt="Cleanup candidate selection" width="49%">
</p>

<p>
  <img src="Docs/Screenshots/cleanup-final-review.png" alt="Final cleanup review" width="49%">
  <img src="Docs/Screenshots/recovery-activity.png" alt="Recovery storage and local activity" width="49%">
</p>

<p>
  <img src="Docs/Screenshots/system-monitor.png" alt="Local system monitor" width="49%">
</p>

## License

Copyright © 2026 Ian Hanna. Second Wind is licensed under
[GPL-3.0-only](LICENSE).

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
- Explain known Applications, Downloads, Documents, Desktop, developer storage,
  caches, logs, and Recovery storage without presenting them as automatic
  cleanup targets.
- Inspect installed apps, their exact known support paths, and possible
  identifier-based orphaned data. Exact identifier paths require review before
  they can enter the normal cleanup plan; ambiguous paths remain protected.
- Check a validated local volume with macOS's read-only verification.

## Storage intelligence

Each completed scan records a local inventory of the locations Second Wind
explicitly understands. The Storage history view groups that inventory into
categories, shows the concrete paths behind a category, and compares it with
the previous scan. It can therefore describe observed growth, shrinkage, and
items that are no longer observed without guessing what macOS's protected or
unknown storage contains.

Recommendations are deterministic explanations of known, eligible items. They
never select, move, or delete anything on their own.

## Application storage

Applications is a read-only projection of that same inventory: it separates an
application bundle from its known related storage, such as support data, caches,
logs, preferences, containers, and developer data. Each relationship includes
its path and association reason. Exact bundle-identifier paths can be shown as
possible orphaned data when the corresponding application is not installed;
they require review before they can enter the normal cleanup plan. Name
matches, ambiguous paths, shared resources, and unknown locations remain
protected. Application-specific selection only adds existing, eligible findings
to the normal review, confirmation, Trash, or Recovery flow.

## Guarantees and limits

- Everything stays on your Mac. No account or network service is required.
- All changes are reviewed and explicitly confirmed before execution. Nothing
  is deleted automatically.
- Recovery items remain locally recoverable until you decide otherwise.
- Ambiguous or sensitive locations stay protected rather than being guessed at.
- Storage recommendations are deterministic local rules; they explain a known
  location, size, and—when available—its local modification date.
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
from System tasks. See the [helper notes](Sources/PrivilegedHelperService/README.md)
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
