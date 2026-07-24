# Second Wind 0.7.0 Preview — Recover & Undo

This preview makes scan and Recovery behaviour easier to follow and safer to
act on. It remains an offline-first macOS preview: nothing changes without a
reviewed, explicit user action.

## Improved

- One provider-based scan path now owns operation identity, cancellation,
  progress, and the completed inventory. The visible scan result is derived
  from that same run.
- Storage observations are reconciled only when providers report the same
  location or parent-child paths overlap. Ordinary observations become direct,
  explainable inventory entries.
- Recovery can verify item integrity before restore, reports damaged items
  without hiding them, and supports multi-item restore or permanent deletion.
- Batch Recovery actions preflight every selected item. A failed restore
  attempts to roll earlier restored items back into Recovery and clearly marks
  anything that still needs attention.
- Restore conflicts require an explicit choice: cancel, restore beside the
  existing item, choose another destination, or separately confirm replacement
  for one item.

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
shasum -a 256 SecondWind-0.7.0-preview.zip
```
