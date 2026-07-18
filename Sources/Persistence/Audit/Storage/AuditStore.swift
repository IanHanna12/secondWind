import Foundation
import SecondWindCore

public struct AuditStore: AuditRecording, Sendable {
    public let auditFileURL: URL

    public init(fileURL: URL? = nil) {
        self.auditFileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecondWind/audit.jsonl")
    }

    /// Appends compact JSON so each audit record occupies one line in the
    /// JSONL file. This deliberately does not use the pretty-printing encoder.
    public func append(_ record: AuditRecord) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: auditFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let handle: FileHandle
        if fileManager.fileExists(atPath: auditFileURL.path) {
            handle = try FileHandle(forWritingTo: auditFileURL)
            try handle.seekToEnd()
        } else {
            guard fileManager.createFile(atPath: auditFileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: auditFileURL)
        }

        defer { try? handle.close() }
        handle.write(data)
        handle.write(Data("\n".utf8))
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
