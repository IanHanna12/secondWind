import Foundation
import Network
import SecondWindCore

/// A small HTTP/1.1 server limited to 127.0.0.1. It serves immutable snapshots
/// only and intentionally has no mutation or scan endpoint.
public final class LocalObservabilityServer: LocalObservabilityServing, @unchecked Sendable {
    private let configuration: LocalObservabilityConfiguration
    private let snapshots: any ObservabilitySnapshotProviding
    private let metrics: any PrometheusMetricsRendering
    private let json: any ObservabilityJSONRendering
    private let queue = DispatchQueue(label: "org.secondwind.observability.http")
    private var listener: NWListener?

    public init(
        configuration: LocalObservabilityConfiguration,
        snapshots: any ObservabilitySnapshotProviding,
        metrics: any PrometheusMetricsRendering = DefaultPrometheusMetricsRenderer(),
        json: any ObservabilityJSONRendering = DefaultObservabilityJSONRenderer()
    ) {
        self.configuration = configuration
        self.snapshots = snapshots
        self.metrics = metrics
        self.json = json
    }

    public func start() async throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .init(configuration.address),
            port: .init(rawValue: configuration.port)!
        )
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: LocalObservabilityError.portUnavailable(self.configuration.port))
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: LocalObservabilityError.serverNotRunning)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            Task {
                let response = await self.response(for: request)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func response(for rawRequest: String) async -> Data {
        let requestLine = rawRequest.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let components = requestLine.split(separator: " ")
        guard components.count >= 2 else { return httpResponse(status: "400 Bad Request") }
        guard components[0] == "GET" else { return httpResponse(status: "405 Method Not Allowed", headers: ["Allow": "GET"]) }

        let path = String(components[1].split(separator: "?", maxSplits: 1).first ?? "")
        let snapshot = await snapshots.snapshot()
        switch path {
        case "/health":
            do {
                return httpResponse(body: try json.health(snapshot: snapshot), contentType: "application/json; charset=utf-8")
            } catch {
                return httpResponse(status: "500 Internal Server Error")
            }
        case "/metrics":
            guard let snapshot else { return httpResponse(status: "503 Service Unavailable") }
            return httpResponse(body: Data(metrics.render(snapshot: snapshot).utf8), contentType: "text/plain; version=0.0.4; charset=utf-8")
        case "/api/v1/summary":
            guard let snapshot else { return httpResponse(status: "503 Service Unavailable") }
            do {
                return httpResponse(body: try json.summary(snapshot: snapshot), contentType: "application/json; charset=utf-8")
            } catch {
                return httpResponse(status: "500 Internal Server Error")
            }
        case "/api/v1/delta/latest":
            guard let snapshot else { return httpResponse(status: "503 Service Unavailable") }
            do {
                return httpResponse(body: try json.latestDelta(snapshot: snapshot), contentType: "application/json; charset=utf-8")
            } catch {
                return httpResponse(status: "500 Internal Server Error")
            }
        default:
            return httpResponse(status: "404 Not Found")
        }
    }

    private func httpResponse(status: String = "200 OK", body: Data = Data(), contentType: String = "text/plain; charset=utf-8", headers: [String: String] = [:]) -> Data {
        var values = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Cache-Control: no-store"
        ]
        values.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        let header = values.joined(separator: "\r\n") + "\r\n\r\n"
        return Data(header.utf8) + body
    }
}

/// Runs the standalone process. Its refresh task reads only already persisted
/// local documents, then replaces the served immutable snapshot atomically.
public final class LocalObservabilityRunner: Runner, @unchecked Sendable {
    private let configuration: LocalObservabilityConfiguration
    private let source: PersistedObservabilitySnapshotProvider
    private let snapshots: LocalObservabilitySnapshotStore
    private let server: LocalObservabilityServer
    private let prometheusFile: PrometheusSnapshotFile?
    private var refreshTask: Task<Void, Never>?

    public init(configuration: LocalObservabilityConfiguration) {
        self.configuration = configuration
        source = .init(includeApplicationMetrics: configuration.includeApplicationMetrics)
        snapshots = .init()
        server = .init(configuration: configuration, snapshots: snapshots)
        prometheusFile = configuration.prometheusFilePath.map {
            PrometheusSnapshotFile(url: URL(fileURLWithPath: $0))
        }
    }

    public func start() async throws {
        await refresh()
        try await server.start()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.configuration.refreshInterval))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    public func stop() async {
        refreshTask?.cancel()
        refreshTask = nil
        await server.stop()
    }

    private func refresh() async {
        let snapshot = await source.snapshot()
        await snapshots.replace(with: snapshot)

        do {
            try prometheusFile?.replace(with: snapshot)
        } catch {
            let message = "Could not update the Prometheus snapshot: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}

/// Publishes the same immutable aggregate snapshot through a read-only file.
/// Docker mounts only this directory; it never receives access to app data.
struct PrometheusSnapshotFile {
    let url: URL

    func replace(with snapshot: LocalObservabilitySnapshot?) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let contents: String
        if let snapshot {
            contents = """
            # HELP secondwind_snapshot_available Whether a completed local snapshot is available.
            # TYPE secondwind_snapshot_available gauge
            secondwind_snapshot_available 1
            \(DefaultPrometheusMetricsRenderer().render(snapshot: snapshot))
            """
        } else {
            contents = """
            # HELP secondwind_snapshot_available Whether a completed local snapshot is available.
            # TYPE secondwind_snapshot_available gauge
            secondwind_snapshot_available 0

            """
        }

        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}
