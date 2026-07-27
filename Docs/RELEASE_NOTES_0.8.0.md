# Second Wind 0.8.0 Preview — Explainability

This preview makes the existing local storage flow inspectable from the first
observation through cleanup review and Recovery. It remains offline-first:
nothing changes automatically, and explanations never authorize a cleanup
action by themselves.

## Improved

- Storage observations and canonical inventory entries retain their identity,
  provider, rule reference, discovery confidence, protection policy and
  supported action. These facts also survive into local snapshots.
- The Inventory Inspector groups the existing Inventory by category,
  application, rule or cleanup status. Each entry explains why it exists, why
  it can or cannot enter a plan, its app relationships and its journey through
  Second Wind. Technical provider, origin and confidence facts stay in the
  entry detail rather than becoming user-facing filters.
- The Rules screen now acts as a read-only rule inspector with approved roots,
  scope, policy, confidence and current matched-inventory previews.
- Application relationships, deterministic recommendations and snapshot deltas
  state the local facts behind their visible conclusions.
- A new Architecture view documents the current local data flow. It adds no
  new storage model or cleanup mechanism.
- Full-path diagnostics export is explicitly confirmed before writing its
  local JSON report.

## Still deliberately excluded

- Automatic or background cleanup
- AI-generated or opaque recommendations
- Cloud sync or telemetry
- Health scores, performance scores, or RAM optimisation
- Additional storage models or hidden heuristics

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
shasum -a 256 SecondWind-0.8.0-preview.zip
```
