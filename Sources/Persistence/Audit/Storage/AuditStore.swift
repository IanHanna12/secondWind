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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let existing = (try? Data(contentsOf: auditFileURL)) ?? Data()
        var updated = existing
        updated.append(data)
        updated.append(Data("\n".utf8))
        try updated.write(to: auditFileURL, options: .atomic)
    }

    public func records() -> [AuditRecord] {
        guard let text = try? String(contentsOf: auditFileURL, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap { try? JSONDecoder.secondWind.decode(AuditRecord.self, from: Data($0.utf8)) }
            .reversed()
    }

    public func exportJSON() throws -> Data {
        try JSONEncoder.secondWind.encode(records())
    }

    public func exportMarkdown() -> String {
        records()
            .map { record in
                "- \(record.timestamp.formatted()) — **\(record.kind.rawValue)**: \(record.result)\n" +
                    "  - Paths: \(record.paths.joined(separator: ", "))"
            }
            .joined(separator: "\n")
    }
}
