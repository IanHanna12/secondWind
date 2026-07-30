import Foundation
import SecondWindCore

/// The Foundation-backed adapter for the application's file-system port.
public struct LocalFileSystem: FileSystem, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }

    /// Returns bytes physically allocated on disk.
    ///
    /// Logical file length is misleading for sparse files such as Docker.raw:
    /// a file may advertise hundreds of gigabytes while occupying only a
    /// small fraction of that space. Cleanup and storage reporting care about
    /// the bytes that can actually be reclaimed.
    public func allocatedSize(at url: URL) -> Int64 {
        guard exists(url) else { return 0 }
        let sizeKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]

        if let values = try? url.resourceValues(forKeys: sizeKeys),
           values.isRegularFile == true {
            return allocatedBytes(from: values)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: sizeKeys),
                  values.isRegularFile == true else {
                continue
            }
            total += allocatedBytes(from: values)
        }
        return total
    }

    /// Returns logical content bytes. Recovery manifests use this stable value
    /// for integrity checks so legacy manifests remain valid.
    public func logicalSize(at url: URL) -> Int64 {
        guard exists(url) else { return 0 }
        let sizeKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

        if let values = try? url.resourceValues(forKeys: sizeKeys),
           values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: sizeKeys),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func allocatedBytes(from values: URLResourceValues) -> Int64 {
        Int64(
            values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
        )
    }

    public func directChildren(in root: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
    }

    public func regularFiles(in root: URL, maximumDepth: Int) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let depth = root.pathComponents.count
        var regularFileURLs: [URL] = []
        for case let url as URL in enumerator {
            if url.pathComponents.count - depth > maximumDepth { enumerator.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { regularFileURLs.append(url) }
        }
        return regularFileURLs
    }
}
