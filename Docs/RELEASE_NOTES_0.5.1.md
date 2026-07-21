# Second Wind 0.5.1 Preview

This patch preview fixes the Recovery screen after larger cleanup actions.

## Fixed

- Recovery storage now appears before activity, so Restore and permanent
  Delete remain immediately accessible.
- The activity timeline starts with the eight newest events. Choose **Show all
  events** only when the full local timeline is needed.

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
shasum -a 256 SecondWind-0.5.1-preview.zip
```
