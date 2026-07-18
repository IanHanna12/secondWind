import Foundation
import SecondWindCore

/// Builds the current, read-only inventory from explicit locations only.
/// It never walks arbitrary user data or turns an observed folder into a
/// cleanup candidate.
public struct StorageInventoryObserver: @unchecked Sendable {
    let home: URL
    private let fileManager: FileManager
    private let fileSystem: LocalFileSystem

    public init(home: URL, fileManager: FileManager = .default) {
        self.home = home.standardizedFileURL
        self.fileManager = fileManager
        fileSystem = LocalFileSystem(fileManager: fileManager)
    }

    public func observe(findings: [Finding], recoveryItems: [RecoveryItem], applications suppliedApplications: [InstalledApplication]? = nil) -> StorageInventory {
        let personalRoots = [
            (name: "Downloads", relativePath: "Downloads", category: StorageCategory.downloads),
            (name: "Documents", relativePath: "Documents", category: StorageCategory.documents),
            (name: "Desktop", relativePath: "Desktop", category: StorageCategory.documents)
        ]
        let roots = personalRoots.map { (name: $0.name, url: home.appendingPathComponent($0.relativePath), category: $0.category) }
        let findingEntries = findings.map { finding in
            let coveredByPersonalRoot = roots.contains { root in
                finding.path == root.url.path || finding.path.hasPrefix(root.url.path + "/")
            }
            return StorageInventoryEntry(
                finding,
                countsTowardCategoryTotal: !coveredByPersonalRoot,
                modifiedAt: modificationDate(at: URL(fileURLWithPath: finding.path))
            )
        }
        let folderEntries = roots.compactMap(personalFolderEntry)
        let applications = suppliedApplications ?? InstalledApplicationInventory(home: home, fileManager: fileManager).applications()
        let applicationEntries = applications.map(applicationEntry)
        let relatedApplicationEntries = ApplicationStorageObserver(home: home, fileManager: fileManager).entries(for: applications)
        let recoveryEntries = recoveryItems.map(StorageInventoryEntry.init)
        let entries = deduplicatedByPath(findingEntries + folderEntries + applicationEntries + relatedApplicationEntries + recoveryEntries)
        let inventory = StorageInventory(entries: entries)
        return ApplicationAssociationResolver(home: home).resolve(inventory: inventory, applications: applications)
    }

    private func personalFolderEntry(name: String, url: URL, category: StorageCategory) -> StorageInventoryEntry? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return StorageInventoryEntry(
            key: "folder|\(category.rawValue)|\(url.path)",
            title: name,
            path: url.path,
            category: category,
            byteSize: fileSystem.fileSize(at: url),
            origin: "Known personal folder",
            explanation: "Second Wind observes the total for this known folder but never treats the folder itself as a cleanup candidate.",
            risk: .protected,
            isActionable: false,
            modifiedAt: modificationDate(at: url)
        )
    }

    private func applicationEntry(_ app: InstalledApplication) -> StorageInventoryEntry {
        StorageInventoryEntry(
            key: "application|\(app.url.path)",
            title: app.displayName,
            path: app.url.path,
            category: .applications,
            byteSize: fileSystem.fileSize(at: app.url),
            origin: "Application inventory",
            explanation: "Application bundle observed locally. Use Applications to inspect its exact support paths before creating a removal plan.",
            risk: .protected,
            isActionable: false,
            modifiedAt: modificationDate(at: app.url)
        )
    }

    private func deduplicatedByPath(_ entries: [StorageInventoryEntry]) -> [StorageInventoryEntry] {
        var entriesByPath: [String: StorageInventoryEntry] = [:]
        for entry in entries {
            let key = entry.path ?? entry.key
            guard let existing = entriesByPath[key] else {
                entriesByPath[key] = entry
                continue
            }
            if entry.isActionable && !existing.isActionable {
                entriesByPath[key] = entry
            }
        }
        return Array(entriesByPath.values)
    }

    private func modificationDate(at url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
