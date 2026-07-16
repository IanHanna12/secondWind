import Foundation
import SecondWindCore

/// The Foundation-backed adapter for the application's file-system port.
public struct LocalFileSystem: FileSystem, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }

    public func fileSize(at url: URL) -> Int64 {
        guard exists(url) else { return 0 }
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
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
