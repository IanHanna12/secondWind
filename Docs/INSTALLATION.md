# Installing Second Wind 1.0

Second Wind 1.0 requires macOS 15 or later. The standard GitHub archive contains
the ready-to-run app and does not include the optional privileged helper.

## Install

1. Download `Second-Wind-1.0.0.zip` and `SHA256SUMS` from the GitHub release.
2. In Terminal, verify the archive from its download directory:

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

3. Extract the archive and move **Second Wind.app** to `/Applications`.
4. Try to open the app once.
5. If macOS blocks it, open **System Settings → Privacy & Security**, select
   **Open Anyway**, and confirm the launch.

This build is currently distributed without Apple Developer ID notarization.
The normal macOS **Open Anyway** flow is preferred; removing quarantine metadata
with `xattr` is neither required nor recommended.

## Upgrade

Quit Second Wind and replace the existing app in `/Applications`. Do not remove
`~/Library/Application Support/SecondWind` during an upgrade. Supported preview
documents are decoded in memory and migrate only when a later write succeeds.

## Uninstall

Remove **Second Wind.app** from `/Applications`. To remove the optional local
observability companion first, run:

```bash
./observability/local-observability stop
```

Recovery payloads and local history are intentionally not deleted with the app.
Review or restore Recovery items before manually removing
`~/Library/Application Support/SecondWind`.
