# Second Wind

> Give your Mac room to breathe.

Second Wind is an offline-first, native macOS 15 Sequoia+ maintenance tool.
It is independently implemented; it contains no third-party cleaning rules,
plugins, remote rule downloads, telemetry, cloud sync, analytics, or update
checks.

## Product philosophy

Second Wind is not a generic “optimizer.” It is a reversible Mac change
manager: understand storage first, make an explicit plan, verify the outcome,
and provide a way back where possible.

- Nothing changes without a visible, reviewed plan.
- Uncertainty increases protection: exact known data can be proposed;
  ambiguous and sensitive data remains review-only or protected.
- Recovery beats deletion. File changes default to local recovery storage, not permanent
  deletion.
- Every change receives a local receipt: what changed, why, how much space it
  affected, and whether it can be restored.
- No performance theatre: no RAM cleaning, invented health scores, or generic
  “speed up your Mac” claims.

**Storage Snapshots** records only the rule findings Second
Wind understands. On later scans it explains meaningful growth or reduction,
shows current free space, and makes the possible effect of a reviewed cleanup
plan visible. It does not index unknown personal files or claim to explain all
of macOS System Data.

## Safety model

- `SecondWindCore` turns bundled, versioned rules into structured findings.
- Findings are classified as **Safe**, **Review Required**, or **Protected**.
  Protected findings cannot enter an executable plan.
- A `CleanupPlan` is dry-run by default and is the only execution input. It
  lists each path, bytes, warnings, destination, and reversibility before a
  separate confirmation step.
- Recovery storage is the default. Payloads plus JSON manifests live in Application
  Support, restore to the original path (without overwriting duplicate names),
  and enter an explicit review queue after 30 days. Items stay recoverable and
  are never deleted automatically.
- Finder Trash is only available for reviewed individual files in Downloads or
  Desktop. Every scan, dry run, execution, failure, restore, and preference
  change can be audited locally and exported as JSON or Markdown.

The app has Dashboard, Storage Snapshots, Live System, Clean Up, Applications,
Maintenance, Settings, and Activity sections. It includes live CPU and memory
readings, storage-outcome previews, an app inventory, exact support-path
matching, and Finder/Dock preferences.

The only current maintenance task is read-only verification of a validated
local volume. Second Wind intentionally excludes privileged maintenance, RAM
cleaning, permission repair, LaunchServices resets, and generic “speed up”
actions.

## Optional privileged helper

The default app is helper-free. An experimental signed XPC helper remains
isolated in [Optional/SecondWindPrivilegedHelper](Optional/SecondWindPrivilegedHelper/README.md),
but it is not built, embedded, advertised, or invoked by the app.

## Build and verify

```bash
swift build --disable-sandbox --scratch-path .build/secondwind-debug

```

For the local GUI build, use the macOS app-bundle launcher rather than the
bare SwiftPM executable:

```bash
./Scripts/run-debug-app.sh
```

The core verification fixture covers rule classification, protected-path
rejection, confirmation and allowlist gates, recovery restore collision
handling, and append-only audit persistence/export using temporary fixtures.

## Xcode release shell

The [Xcode](Xcode/README.md) directory provides the direct-notarization
packaging shell: a default app scheme plus an optional helper scheme, stable
identifiers, hardened runtime, and the workspace. Generate
`SecondWind.xcodeproj` from `project.yml` with XcodeGen, set the real
signing team, then archive and notarize with Xcode.
