# Second Wind 0.6.0 Preview — Operational Trust

This preview strengthens the local path from scan through review, cleanup, and
Recovery. It remains a conservative, offline-first macOS preview: nothing is
changed automatically, and every cleanup action still requires review and
explicit confirmation.

## Improved

- Scan, cleanup, Recovery, and relevant activity share clearer operation
  identity, progress, cancellation, and typed outcomes.
- Incomplete scans do not replace the last completed inventory. Observations
  are reconciled only for overlapping or conflicting paths, preserving their
  origins without double-counting storage.
- Cleanup reports a result for each requested item and performs a focused,
  read-only verification after execution.
- Recovery and rule-policy records retain versioned context for later
  explanation and compatibility handling.
- Cleanup selection remains responsive with larger result sets: selecting one
  item updates only that item and the aggregate selection counters.

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
shasum -a 256 SecondWind-0.6.0-preview.zip
```
