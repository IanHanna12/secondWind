# Second Wind v1 Stability Contract

Second Wind 1.0 stabilizes the existing product boundaries. It does not create
a second inventory, cleanup workflow, Recovery model, history, or observability
source of truth.

## Authoritative flow

```text
Read-only scan → reconciled inventory → explanation → user selection
→ reviewed plan → explicit confirmation → Trash or Recovery
→ focused verification → Activity → restore or permanent deletion
```

Only a completed scan replaces the previous completed inventory. Ambiguous
storage remains protected. Observability consumes already persisted facts and
cannot start scans or mutate storage.

## Versioned data

| Contract | v1 behavior |
| --- | --- |
| Storage snapshots | Legacy arrays remain readable; successful writes use schema 1. |
| Activity and audit | Legacy JSONL remains readable; successful appends rewrite atomic schema-1 lines. |
| Recovery manifests | Legacy manifests remain restorable when their payload and identity are valid; new manifests use schema 1. |
| Rule policy | Missing legacy schema is supported; future, corrupt, or invalid policies stay untouched and built-in rules are used. |
| Observability JSON API | `/health`, summary, and latest delta declare `schemaVersion: 1`. |
| Prometheus | Published `secondwind_*` metric names remain compatible throughout v1.x. |

Durable JSON writes use atomic replacement. An unsupported future schema or
damaged document blocks replacement and preserves the original bytes. Reading a
legacy document alone never rewrites it.

During v1.x, existing public fields and metric names are not removed or renamed
incompatibly. Optional fields and new bounded metrics may be added. A breaking
format change requires migration support or a new major version.

## Safety and privacy

- Scans are read-only; filesystem work does not run on the Main Actor.
- Every storage mutation is explicitly selected, reviewed, confirmed, audited,
  and given a typed per-action result.
- Restore never silently replaces an existing item. Permanent Recovery deletion
  requires separate confirmation.
- Recovery has no automatic retention deletion.
- Local observability is optional, loopback-only, read-only, aggregated, and
  contains no paths, file names, user names, Recovery references, arbitrary rule
  names, or application identifiers by default.
- Second Wind has no remote telemetry. Deliberate full-path diagnostic exports
  remain a separate user-initiated action.

## Known limitations

- Second Wind explains only locations its providers and rules explicitly know;
  it does not claim to explain all macOS System Data.
- APFS allocation, snapshots, clones, and purgeable storage mean planned bytes,
  moved bytes, verified bytes, and observed free-space change may differ.
- The standard release is not notarized, and the optional privileged helper is
  not included.
- Application associations are conservative and do not make uncertain storage
  eligible for cleanup.
- Local observability needs a completed stored snapshot before data endpoints
  can return metrics.
- Support is best effort; there is no guaranteed response time or release
  schedule.

See [Installation](INSTALLATION.md), [Architecture](ARCHITECTURE.md), the
[observability guide](../observability/README.md), [Security](../SECURITY.md),
and [Contributing](../CONTRIBUTING.md).
