import Foundation
import LocalObservability

@main
struct LocalObservabilityCLI {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let configuration = try LocalObservabilityConfiguration(
                port: options.port,
                includeApplicationMetrics: options.includeApplicationMetrics,
                prometheusFilePath: options.prometheusFilePath
            )
            let runner = LocalObservabilityRunner(configuration: configuration)
            try await runner.start()
            print("Second Wind Local Observability listening on http://127.0.0.1:\(options.port)")
            print("Read-only endpoints: /health, /metrics, /api/v1/summary, /api/v1/delta/latest")
            await waitForTerminationSignal()
            await runner.stop()
        } catch {
            FileHandle.standardError.write(Data("Second Wind Local Observability: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func waitForTerminationSignal() async {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        await withCheckedContinuation { continuation in
            var receivedSignal = false
            let finish = {
                guard !receivedSignal else { return }
                receivedSignal = true
                continuation.resume()
            }
            interrupt.setEventHandler(handler: finish)
            terminate.setEventHandler(handler: finish)
            interrupt.resume()
            terminate.resume()
        }

        // The sources stay alive while the task is awaiting a signal. Once one
        // arrives, this function returns and the process can stop cleanly.
        withExtendedLifetime(interrupt) {}
        withExtendedLifetime(terminate) {}
    }
}

private struct Options {
    let port: UInt16
    let includeApplicationMetrics: Bool
    let prometheusFilePath: String?

    init(arguments: [String]) throws {
        var port: UInt16 = 9467
        var includeApplicationMetrics = false
        var prometheusFilePath: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--port":
                index += 1
                guard index < arguments.count, let parsedPort = UInt16(arguments[index]) else {
                    throw LocalObservabilityError.invalidPort
                }
                port = parsedPort
            case "--application-metrics":
                includeApplicationMetrics = true
            case "--prometheus-file":
                index += 1
                guard index < arguments.count else {
                    throw LocalObservabilityError.invalidPrometheusFile
                }
                prometheusFilePath = arguments[index]
            case "--help", "-h":
                print("""
                Usage: secondwind-observability [--port 9467] \
                [--application-metrics] [--prometheus-file PATH]
                """)
                Foundation.exit(0)
            default:
                throw LocalObservabilityError.invalidPort
            }
            index += 1
        }
        self.port = port
        self.includeApplicationMetrics = includeApplicationMetrics
        self.prometheusFilePath = prometheusFilePath
    }
}
