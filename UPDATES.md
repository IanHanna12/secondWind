# Updates

This is a short, dated record of visible changes to Second Wind. It is not a
release log: Second Wind has no release cadence, version tags, or update
service. App versions describe development stages; for the precise source
behind any change, use the linked Git commit.

## Current public development version

**0.2.0** — Granular cleanup review. Cache rules can show individual direct
children for independent review, app support paths disclose how they were
matched, and Recovery gives every stored item a clear reference. Interfaces,
rules, and stored formats may still change incompatibly.

## 17 July 2026

- Cleanup findings for rebuildable developer and package caches are now shown
  per direct child where possible. Each candidate has its own path, size, and
  explanation before it can be selected.
- Application removal previews label exact bundle-ID matches separately from
  conservative name-based matches, so uncertain support data remains visible
  as uncertain.
- Recovery history now displays the original location, stored size and time,
  and a stable Recovery reference for each item.

## 16 July 2026

- [Safe rule management](https://github.com/IanHanna12/secondWind/commit/6e939bd):
  added an in-app Rules screen for inspecting and enabling bundled rules,
  creating local rules from approved routes, and exporting the local policy as
  JSON. Direct Trash actions now accept only current, executable scan findings
  and retain their rule versions in the audit trail.
- [Source organization](https://github.com/IanHanna12/secondWind/commit/e28d58f):
  replaced the broad Infrastructure and Snapshots modules with System and
  Persistence, and grouped source by precise responsibility.
  Examples include Applications/Inventory/Preview, Applications/Removal/Trash,
  System/Resolver/Process, and Persistence/Snapshots/Storage.
- [Build identity](https://github.com/IanHanna12/secondWind/commit/e990f7c):
  Xcode-built apps show their source revision and build time in Settings. A
  build made with local uncommitted changes is clearly marked as dirty.
- Initial public source published, including local Recovery, review-required
  cleanup plans, audited actions, storage snapshots, and the optional tightly
  scoped privileged helper.
