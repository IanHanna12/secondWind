# Updates

This is a short, dated record of visible changes to Second Wind. App versions
describe development stages; for the precise source behind any change, use the
linked Git commit.

## Current public development version

**1.0.0 — Stable Foundation:** the existing scan, inventory, explainability,
reviewed cleanup, Recovery, history, rules, and optional local observability
flow now has a documented compatibility and migration contract. The release is
still distributed directly and without Apple notarization, but it is no longer
labelled as a data-format preview.

## 2 August 2026

- Added schema-versioned envelopes for Storage Snapshots, Activity records,
  and Recovery manifests. Supported preview formats remain readable and are
  migrated only on the next successful write.
- Unsupported future and damaged durable documents are left untouched and
  block replacement instead of silently erasing the previous state.
- Every JSON API v1 response now identifies its schema version. Existing
  Prometheus metric names and JSON API v1 fields form a compatibility contract
  for the v1.x line.
- A damaged or unsupported local rule policy is visibly replaced by safe
  built-in rules for the current session while the original document remains
  untouched.
- Added stable installation, migration, privacy, support, security, and known
  limitation documentation, plus structured bug and feature request forms.
- Reworked release packaging around `Second-Wind-1.0.0.zip` and a shared
  `SHA256SUMS` file, with version, build, revision, resources, helper exclusion,
  signing consistency, and user-data checks.
- Removed inactive Finder, Dock, and menu-bar preference controls.

## 30 July 2026

- Added the optional `observability` companion with read-only `/health`,
  `/metrics`, `/api/v1/summary`, and `/api/v1/delta/latest` endpoints bound to
  `127.0.0.1`. It does not trigger scans or expose cleanup operations.
- Prometheus metrics and JSON responses contain aggregate categories, scan,
  Recovery, and cleanup facts without paths, file names, user names, Recovery
  references, rule names, or application identities.
- Included an optional local Prometheus and Grafana setup with a provisioned
  Second Wind overview dashboard. Application metrics remain disabled by
  default.
- The one-command setup installs the native endpoint as a user `LaunchAgent`
  with health checks and automatic restart. Prometheus consumes only an atomic,
  redacted metrics snapshot through an internal Docker bridge; it receives no
  access to Second Wind's local documents.
- Grafana provisions its Prometheus data source and overview dashboard
  automatically. Current category bars are visible from the first scrape, and
  history panels refresh every 15 seconds.
- Storage measurements now use allocated disk space throughout scanning,
  Recovery, and observability. Sparse files therefore report the space they
  occupy rather than their logical maximum size; Recovery integrity continues
  to verify each manifest's logical payload size.
- Added the current Grafana dashboard screenshots to the repository and made
  its scan-snapshot and live-Recovery time bases explicit.
- Simplified the source tree and introduced a single visible application flow:
  app entry, runtime composition, workflows, services, persistence, and macOS
  adapters. Direct Finder Trash cleanup now uses the same operation workflow as
  reviewed cleanup.
- Technical `.noindex` suffixes remain in exact stored paths but are omitted
  from friendly cleanup titles and compact path labels.

## 27 July 2026

- Inventory entries retain their observed identity, provider, rule reference,
  discovery confidence and supported action through reconciliation and local
  snapshots. Older snapshots remain readable with safe defaults.
- The new Inventory Inspector groups the existing canonical inventory by
  category, application, rule or cleanup status, then shows the path, facts,
  protection or cleanup reasons, and storage journey for each entry. Technical
  provider, origin and confidence facts remain in the entry detail.
- Rules now expose their approved root, scope, protection behaviour, supported
  action, confidence and read-only current-inventory preview.
- Application relationships, snapshot deltas and deterministic
  recommendations explain the existing facts behind their visible conclusions.
- Diagnostics export requires an explicit confirmation before producing a
  full-path JSON report with inventory metadata, Recovery references and
  activity records.
- An Architecture view maps the existing local flow from observation providers
  through inventory, review, Recovery and activity without creating another
  workflow.

## 24 July 2026

- A single scan runner now owns provider execution, operation identity,
  cancellation, progress, and the completed inventory. The UI adapts that one
  result rather than starting a second scan.
- Only duplicate or parent-child-overlapping storage observations are sent to
  reconciliation; ordinary observations become inventory entries directly.
- Recovery supports integrity checks, batch preflight, rollback reporting, and
  explicit restore-conflict choices. Restore and permanent deletion record a
  result for every selected item.
- Local audit, Recovery, rule-policy, and snapshot persistence are reached
  through one local data store at the app boundary.

## 23 July 2026

- Cleanup selection updates only the selected item and its aggregate counters;
  filtering, sorting, category totals, and review explanations are prepared
  when scan results or filters change instead of on every click.
- Scan and cleanup flows now share operation identity, progress, cancellation,
  typed failures, and local activity where appropriate.
- Scan results are collected as observations, then reconciled only when paths
  overlap or conflict. Incomplete scans do not replace the last completed view.
- Cleanup records explicit action outcomes and performs a focused read-only
  verification after execution.
- Recovery and policy persistence carry schema and context information forward
  rather than inferring historical context from the current machine.

## 21 July 2026

- Recovery storage now appears before activity, keeping Restore and permanent
  Delete directly accessible.
- Recovery activity starts with the eight newest events and can expand on
  demand, instead of displacing the stored items below the fold.

## 20 July 2026

- Cleanup review now shows why every candidate was suggested, whether its data
  can be regenerated, its protection status, and whether Recovery is available
  before the user creates a cleanup plan.
- Storage intelligence now presents an explicit dashboard for growth and
  shrinkage since the previous scan, largest changed categories, and a compact
  local scan history. These views are derived from the existing snapshots; no
  parallel history is stored.
- Recovery activity is grouped into a local, day-based timeline alongside the
  current Recovery items and audit activity.
- Added an architecture map describing the flow from local scan input through
  facts, snapshot history, preview read models, user decisions, and Recovery.

## 18 July 2026

- Applications now groups known inventory entries by installed application,
  separating application bundles, related data, and total known storage without
  presenting bundle size as the full footprint.
- Every displayed relationship includes its exact known path, its association
  reason, evidence, data kind, and current cleanup status. Associations do not
  change an existing entry's eligibility or protection.
- Exact bundle-identifier paths without a matching installed application are
  shown as possible orphaned data requiring review. They can enter the normal
  cleanup plan, where Recovery is the default destination. Name matches,
  ambiguous paths, shared resources, and unknown locations remain protected.
- Application storage changes compare the same persisted inventory snapshots
  used by Storage history; no second application-history system is created.
- Application-specific selection only chooses existing eligible findings, then
  continues through the normal review, confirmation, Finder Trash, or Recovery
  workflow.
- Storage scanning is now coordinated by `SecondWindServices` rather than the
  SwiftUI view model. The service owns the detached filesystem worker and
  emits progress and completion events; UI state remains on the Main Actor.

### Earlier the same day

- Storage intelligence: a shared local inventory now powers storage
  categories, a category explorer, scan summaries, and comparison with the
  previous snapshot.

- Storage overview groups known local storage into explainable categories,
  including Applications, Downloads, Documents, Developer Storage, Caches,
  Logs, Recovery Storage, and Other / System Data. It explicitly does not
  claim to explain all macOS System Data.
- Each category can be expanded into its concrete, known paths, origin, size,
  and cleanup status.
- Snapshot comparison now aggregates category growth and shrinkage, while
  preserving detailed per-entry changes. A missing entry is described as no
  longer observed, never assumed deleted.
- The latest scan reports its duration, finding count, eligible, review-required
  and protected items, and observed storage.
- Cleanup labels explain whether an item is recreated automatically, requires
  review, or is protected instead of using a generic “Safe” label.
- A dedicated Developer Storage screen makes known Xcode, Docker, package,
  simulator, archive, and other developer locations reviewable independently.
- Explainable recommendations use deterministic local rules for known large
  storage and, where a local modification date is available, older large files.
  They never select or clean anything automatically.

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
  Examples include macOS/Applications/Inventory/Preview, macOS/Finder/Trash,
  macOS/Processes, and Persistence/Snapshots/Storage.
- [Build identity](https://github.com/IanHanna12/secondWind/commit/e990f7c):
  Xcode-built apps show their source revision and build time in Settings. A
  build made with local uncommitted changes is clearly marked as dirty.
- Initial public source published, including local Recovery, review-required
  cleanup plans, audited actions, storage snapshots, and the optional tightly
  scoped privileged helper.
