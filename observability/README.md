# Second Wind Local Observability

This is an optional, standalone local companion to Second Wind. It does not
change the app, trigger scans, mutate storage, or contact the network. It reads
only the app's existing local snapshots, Recovery manifests and activity
records, then serves one immutable aggregate snapshot on `127.0.0.1`.

It is deliberately separate from the Second Wind app. Start it only when you
want Prometheus or Grafana to visualize the already persisted local history.

## One-command setup

Docker Desktop is the only external requirement. From the repository root:

```bash
./observability/local-observability
```

The script builds and installs the native read-only endpoint as a macOS
`LaunchAgent`, starts Prometheus and Grafana, waits until all services are
ready, verifies the first real data point, and then opens Grafana. The
`LaunchAgent` uses `RunAtLoad` and `KeepAlive`, so it is not tied to the
terminal process that started it.

Observability is its own Swift package inside the Second Wind repository. It
does not appear in the main app's navigation and does not modify or become a
dependency of any existing package. Grafana is its optional user interface.

```bash
./observability/local-observability status
./observability/local-observability logs
./observability/local-observability stop
```

| Local service | Address |
| --- | --- |
| Grafana | `http://127.0.0.1:3000` (`admin` / `admin`) |
| Prometheus | `http://127.0.0.1:9090` |
| Second Wind metrics | `http://127.0.0.1:9467/metrics` |

The Docker-specific configuration lives in the repository's top-level
`docker/` directory. The native endpoint stays outside Docker because it reads
Second Wind's macOS-local documents.

The loopback-only server atomically publishes the same redacted Prometheus
snapshot into its private runtime directory. Docker mounts only that metrics
directory read-only. An internal Nginx bridge serves the snapshot to
Prometheus; it publishes no host port and cannot access Second Wind's documents.
This preserves the `127.0.0.1` boundary without relying on Docker Desktop host
network forwarding.

## Run only the native endpoint

From the `observability` directory:

```bash
swift run secondwind-observability
swift run secondwind-observability --port 9468
swift run secondwind-observability --application-metrics
```

Application metrics are disabled by default. When enabled, they expose only
aggregate bytes and counts: no application name, bundle identifier, or path
becomes a metric label.

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /health` | Server and local-snapshot availability. |
| `GET /metrics` | Prometheus text exposition format. |
| `GET /api/v1/summary` | Aggregated inventory, scan, Recovery and cleanup JSON. |
| `GET /api/v1/delta/latest` | Latest category-level snapshot delta JSON. |

All endpoints are read-only. Unknown paths return `404`; non-`GET` requests
return `405`. If Second Wind has not saved a snapshot yet, `/health` reports
`waiting_for_snapshot` and the data endpoints return `503`.

## Privacy boundary

The exported snapshot never contains:

- paths, file names, user names or home-directory values;
- Recovery references or Recovery item identifiers;
- rule names, rule identifiers or arbitrary provider names;
- application names or bundle identifiers.

Fixed storage category keys are the only metric labels. The server is bound to
the IPv4 loopback address by construction; a different host is rejected before
the listener starts. Requests are not individually recorded.

## Development checks

```bash
swift test
swift run secondwind-observability
curl http://127.0.0.1:9467/health
curl http://127.0.0.1:9467/metrics
```
