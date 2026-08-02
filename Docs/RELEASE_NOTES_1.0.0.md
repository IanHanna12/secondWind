# Second Wind 1.0.0 — Stable Foundation

Second Wind 1.0 stabilizes its existing native macOS storage workflow. It keeps
one canonical inventory, one reviewed cleanup path, one Recovery model, one
durable history, and one optional local observability boundary.

## Highlights

- Versioned, atomically replaced Storage Snapshot, Activity, Recovery, and rule
  policy documents with safe preview-data migration.
- Explicit schema versioning for all JSON API v1 responses and a v1.x
  compatibility promise for public Prometheus metrics.
- Visible safe fallback when a stored rule policy is damaged, invalid, or from
  a newer unsupported version.
- Reproducible standard app packaging with version, build, revision, minimum
  macOS, resources, helper exclusion, and SHA-256 validation.
- Installation, compatibility, privacy, limitations, support, contribution,
  and security documentation.
- Removal of inactive Finder, Dock, and menu-bar preference controls that did
  not provide a verifiable operation result.

## Distribution

The archive contains the standard app without the optional privileged helper.
It is ad-hoc signed and not notarized. macOS may require approval through
**System Settings → Privacy & Security → Open Anyway** on first launch. Do not
remove quarantine metadata; use macOS's normal approval flow.

Second Wind 1.0 requires macOS 15 or later. Verify the release archive with the
published `SHA256SUMS` file before installing it.
