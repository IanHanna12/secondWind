import Darwin
import Foundation
import Metal

public struct MemoryPopulation: Sendable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let pressureLabel: String
    public var usedFraction: Double { Double(usedBytes) / Double(max(1, totalBytes)) }
}

public struct LiveSystemMetrics: Sendable {
    public let cpuUtilization: Double?
    public let memory: MemoryPopulation
    public let gpuName: String?
    public let capturedAt: Date

    public static let unavailable = LiveSystemMetrics(
        cpuUtilization: nil,
        memory: MemoryPopulation(totalBytes: 0, usedBytes: 0, availableBytes: 0, pressureLabel: "Calculating…"),
        gpuName: nil,
        capturedAt: .distantPast
    )
}

/// A local sampler. CPU is computed from the delta between consecutive kernel CPU-tick samples.
public final class LiveMetricsService: @unchecked Sendable {
    private var previousCPUTicks: (total: UInt64, idle: UInt64)?

    public init() {}

    public func sample() -> LiveSystemMetrics {
        let ticks = cpuTicks()
        let cpu: Double?
        if let previous = previousCPUTicks {
            let totalDelta = ticks.total &- previous.total
            let idleDelta = ticks.idle &- previous.idle
            cpu = totalDelta == 0 ? nil : min(1, max(0, 1 - Double(idleDelta) / Double(totalDelta)))
        } else {
            cpu = nil
        }
        previousCPUTicks = ticks
        return LiveSystemMetrics(cpuUtilization: cpu, memory: memoryPopulation(), gpuName: MTLCreateSystemDefaultDevice()?.name, capturedAt: Date())
    }

    private func cpuTicks() -> (total: UInt64, idle: UInt64) {
        var cpuInfo: processor_info_array_t?
        var processorCount: mach_msg_type_number_t = 0
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &cpuInfo, &infoCount) == KERN_SUCCESS, let cpuInfo else { return (0, 0) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let stride = Int(CPU_STATE_MAX)
        var total: UInt64 = 0; var idle: UInt64 = 0
        for index in 0..<Int(processorCount) {
            let base = index * stride
            total += UInt64(cpuInfo[base + Int(CPU_STATE_USER)])
            total += UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            total += UInt64(cpuInfo[base + Int(CPU_STATE_NICE)])
            let idleTicks = UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            idle += idleTicks; total += idleTicks
        }
        return (total, idle)
    }

    private func memoryPopulation() -> MemoryPopulation {
        var pageSize: vm_size_t = 0; host_page_size(mach_host_self(), &pageSize)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return MemoryPopulation(totalBytes: total, usedBytes: 0, availableBytes: 0, pressureLabel: "Unavailable") }
        let bytes: (UInt64) -> Int64 = { Int64($0 * UInt64(pageSize)) }
        // Match Activity Monitor's mental model more closely: wired + active +
        // compressed pages are occupied; inactive and purgeable cache pages are
        // readily reusable and should not make normal memory look "90% used".
        let used = min(total, bytes(UInt64(stats.wire_count) + UInt64(stats.active_count) + UInt64(stats.compressor_page_count)))
        let available = max(0, total - used)
        let ratio = Double(available) / Double(max(1, total))
        let pressure = ratio > 0.15 ? "Normal" : ratio > 0.07 ? "Elevated" : "High"
        return MemoryPopulation(totalBytes: total, usedBytes: used, availableBytes: available, pressureLabel: pressure)
    }
}
