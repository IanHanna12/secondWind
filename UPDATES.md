# Updates

This is a short, dated record of visible changes to Second Wind. It is not a
release log: Second Wind has no release cadence, version tags, or update
service. For the precise source behind any change, use the linked Git commit.

## 16 July 2026

- Source organization: replaced the broad Infrastructure and Snapshots modules
  with System and Persistence, and grouped source by precise responsibility.
  Examples include Applications/Inventory/Preview, Applications/Removal/Trash,
  System/Resolver/Process, and Persistence/Snapshots/Storage.
- [Build identity](https://github.com/IanHanna12/secondWind/commit/e990f7c):
  Xcode-built apps show their source revision and build time in Settings. A
  build made with local uncommitted changes is clearly marked as dirty.
- Initial public source published, including local Recovery, review-required
  cleanup plans, audited actions, storage snapshots, and the optional tightly
  scoped privileged helper.
