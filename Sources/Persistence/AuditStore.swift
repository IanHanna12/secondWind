import Foundation
import SecondWindCore

public struct AuditStore: AuditStoring, Sendable {
    public let auditFileURL: URL

    public init(fileURL: URL? = nil) {
        self.auditFileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecondWind/audit.jsonl")
    }

    /// Updates the JSONL document by atomic replacement. It retains the
    /// line-oriented format while preventing an interrupted append from
    /// leaving a half-written activity record behind.
    public func append(_ record: AuditRecord) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: auditFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var storedRecords = try loadStoredRecords()
        storedRecords.append(record)
        let lines = try storedRecords.map { record in
            try PersistenceDocumentCodec.encodeLine(record)
        }
        var document = Data()
        for line in lines {
            document.append(line)
            document.append(Data("\n".utf8))
        }
        try document.write(to: auditFileURL, options: .atomic)
    }

    public func records() -> [AuditRecord] {
        Array(((try? loadStoredRecords()) ?? []).reversed())
    }

    public func exportJSON() throws -> Data {
        try PersistenceDocumentCodec.encode(records())
    }

    public func exportMarkdown() -> String {
        records()
            .map { record in
                "- \(record.timestamp.formatted()) — **\(record.kind.rawValue)**: \(record.result)\n" +
                    "  - Paths: \(record.paths.joined(separator: ", "))"
            }
            .joined(separator: "\n")
    }

    public func loadRecords() throws -> [AuditRecord] {
        Array(try loadStoredRecords().reversed())
    }

    private func loadStoredRecords() throws -> [AuditRecord] {
        guard FileManager.default.fileExists(atPath: auditFileURL.path) else { return [] }
        let text = try String(contentsOf: auditFileURL, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            let data = Data(line.utf8)
            return try PersistenceDocumentCodec.decode(
                AuditRecord.self,
                from: data,
                documentName: "activity"
            ) {
                try JSONDecoder.secondWind.decode(AuditRecord.self, from: data)
            }
        }
    }
}
