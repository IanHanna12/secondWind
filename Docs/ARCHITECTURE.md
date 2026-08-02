# Second Wind — architecture map

One diagram, one primary flow. Detailed responsibilities are inside the nodes,
so Mermaid does not need to draw crossing links for every individual type.

```mermaid
flowchart TB
    Person([Mac owner])

    Input["<b>1 · Local inputs</b><br/>Built-in and enabled local rules<br/>Explicit known local paths<br/>Installed application discovery"]

    Scan["<b>2 · Read-only scan workflow</b><br/>LocalStorageScanService<br/>LocalScanRunner<br/>Storage inventory providers + capture<br/>Application association resolver"]

    Facts["<b>3 · Shared domain facts</b><br/>Findings: reason, size, risk, action<br/>StorageInventory: identity, provider, rule, confidence<br/>ApplicationInventory: read-only grouping"]

    History["<b>4 · Local durable history</b><br/>Audit records<br/>Recovery items and payloads<br/>Snapshots and snapshot report"]

    ReadModels["<b>5 · Derived explanations</b><br/>Inventory inspector: facts, protection, journey<br/>Cleanup review and recommendations: explicit reasons<br/>Storage delta and history: snapshot causes<br/>Recovery timeline: cleanup and Recovery by day"]

    Screens["<b>6 · Native macOS screens</b><br/>Clean Up · Storage overview · Inventory inspector<br/>Applications · Rules · Architecture · Recovery"]

    Plan["<b>7 · Reviewed CleanupPlan</b><br/>Dry run → warnings → explicit confirmation<br/>Protected or unsupported items are blocked"]

    Recovery["<b>8a · Local Recovery</b><br/>Payload + manifest<br/>Explicit restore or permanent delete"]
    Trash["<b>8b · Finder Trash</b><br/>User-selected final destination"]

    Helper["<b>Optional privileged branch</b><br/>Typed XPC request only<br/>Signed caller validation<br/>Fixed maintenance operations"]

    Release["<b>Separate release distribution branch</b><br/>Xcode build → smoke checks → app ZIP<br/>SHA-256 → GitHub release"]

    Person -->|starts a local scan| Input
    Input --> Scan
    Scan -->|no filesystem changes| Facts
    Facts -->|audit and snapshot capture| History
    Facts --> ReadModels
    History --> ReadModels
    ReadModels --> Screens
    Person -->|reviews and chooses| Screens
    Screens -->|only selected executable findings| Plan
    Plan -->|Keep in Recovery| Recovery
    Plan -->|Move to Finder Trash| Trash
    Screens -. user-confirmed system task only .-> Helper
    Release -. app ZIP download only; never a runtime dependency .-> Person

    classDef input fill:#eceff1,stroke:#607d8b,color:#263238
    classDef workflow fill:#e3f2fd,stroke:#1565c0,color:#0d47a1
    classDef stored fill:#fff8e1,stroke:#f9a825,color:#5f4b00
    classDef derived fill:#e8f5e9,stroke:#2e7d32,color:#1b5e20
    classDef ui fill:#f3e5f5,stroke:#7b1fa2,color:#4a148c
    classDef action fill:#fff3e0,stroke:#ef6c00,color:#e65100
    class Input input
    class Scan,Facts workflow
    class History stored
    class ReadModels derived
    class Screens ui
    class Plan,Recovery,Trash,Helper,Release action
```

## Reading rules

- The vertical spine is the only data flow: local inputs become shared facts,
  shared facts are recorded locally, and the screens render derived views.
- The green node contains no new persistence or policy. It only turns existing
  facts into review, delta, history and timeline explanations.
- The orange cleanup branch is the only route that changes storage. It requires
  a reviewed plan and ends in local Recovery or Finder Trash.
- The helper and release pipeline are isolated side branches. Normal scanning,
  explanation, recovery and restore never require either one.
