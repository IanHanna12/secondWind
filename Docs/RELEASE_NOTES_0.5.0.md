# Second Wind 0.5.0 Preview

Second Wind 0.5.0 is the first directly usable preview of the app. It is built
for understanding local storage before making a deliberate cleanup decision.

## What is new

- Cleanup review explains why a candidate was suggested, its potential space
  recovery, whether it can regenerate, its protection status, and its Recovery
  option.
- Storage intelligence shows the most meaningful changes since the previous
  scan, including category growth, shrinkage, and local scan history.
- Recovery activity is collected into a readable timeline grouped by day.
- The architecture map documents how local scans become inventory, snapshots,
  explainable views, reviewed cleanup plans, audit history, and Recovery.

## Preview installation

This build is locally distributed and **not notarized**. macOS may block its
first launch. After trying to open Second Wind once, open **System Settings →
Privacy & Security** and choose **Open Anyway** for the app.

The optional privileged helper is not part of this preview distribution. All
storage scanning, review, cleanup planning, Finder Trash, Recovery, audit, and
snapshot features work without it.

## Verification

The release includes a SHA-256 checksum for the ZIP file. Verify it before
opening the app:

```bash
shasum -a 256 SecondWind-0.5.0-preview.zip
```

## Known preview limits

- The app supports macOS 15 or later.
- Interfaces, rules, and stored formats may still change incompatibly.
- Second Wind only describes and acts on local locations it explicitly
  understands. Ambiguous and sensitive locations remain protected.
