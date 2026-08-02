import Foundation
import Darwin
import SecondWindCore

public struct ProcessUsage: Identifiable, Hashable, Sendable {
    public let pid: Int
    public let command: String
    public let cpuPercent: Double
    public let residentMemoryBytes: Int64

    public var id: Int { pid }
}

public struct DashboardSnapshot: Snapshot {
    public let storageTotal: Int64
    public let storageAvailable: Int64
    public let physicalMemory: UInt64
    public let activeProcessors: Int
    public let loadAverage: Double
    public let topProcesses: [ProcessUsage]
    public let capturedAt: Date

    public var storageUsed: Int64 { max(0, storageTotal - storageAvailable) }
}

public struct MonitorService: Service {
    public init() {}

    public func snapshot(includeProcesses: Bool = false) -> DashboardSnapshot {
        let volumeValues = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])

        return DashboardSnapshot(
            storageTotal: Int64(volumeValues?.volumeTotalCapacity ?? 0),
            storageAvailable: Int64(volumeValues?.volumeAvailableCapacityForImportantUsage ?? 0),
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            activeProcessors: ProcessInfo.processInfo.activeProcessorCount,
            loadAverage: currentLoadAverage(),
            topProcesses: includeProcesses ? topProcesses() : [],
            capturedAt: Date()
        )
    }

    private func currentLoadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        return loads[0]
    }

    private func topProcesses() -> [ProcessUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        guard let output = process.standardOutput as? Pipe,
              (try? process.run()) != nil else {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap(parseProcessUsage)
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(5)
            .map { $0 }
    }

    private func parseProcessUsage(_ line: Substring) -> ProcessUsage? {
        let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 4,
              let pid = Int(fields[0]),
              let cpuPercent = Double(fields[1]),
              let residentKilobytes = Int64(fields[2]) else {
            return nil
        }
        return ProcessUsage(
            pid: pid,
            command: String(fields[3]),
            cpuPercent: cpuPercent,
            residentMemoryBytes: residentKilobytes * 1_024
        )
    }
}
