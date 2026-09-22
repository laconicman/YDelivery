import Foundation

/// The on-device capture an engaged user can share — one JSON object per HTTP exchange,
/// bounded, in Application Support.
///
/// Why a file and not `OSLog`: `OSLogStore(scope: .currentProcessIdentifier)` drops
/// everything logged before the current launch, and public bodies would sit in the device
/// log where a sysdiagnose can read them. A file in the app container survives relaunch —
/// the exact case "I hit a weird response, then reopened the app to share it" needs —
/// and leaves the device only through an explicit share sheet (firefox-ios's
/// `copyLogsToDocuments` is the same pattern).
///
/// The file holds request and response bodies verbatim — addresses, names, phone numbers.
/// Sharing it is the user's act; the Settings label says so (YD-12).
actor WireLogStore {
    /// One exchange, one JSONL line.
    struct Entry: Encodable, Sendable {
        let at: Date
        let operation: String
        let method: String
        let path: String
        var status: Int?
        var requestBody: String?
        var responseBody: String?
        var error: String?

        init(
            at: Date, operation: String, method: String, path: String,
            status: Int? = nil, requestBody: String? = nil,
            responseBody: String? = nil, error: String? = nil
        ) {
            self.at = at
            self.operation = operation
            self.method = method
            self.path = path
            self.status = status
            self.requestBody = requestBody
            self.responseBody = responseBody
            self.error = error
        }
    }

    /// The file this store appends to. Constant, so views can share it without awaiting.
    nonisolated let fileURL: URL

    /// Re-publishes `exportURL` after every mutation — the share affordance mirrors
    /// this stream instead of snapshotting the file on appear (review, PR #33).
    nonisolated let exportURLChanges: AsyncStream<URL?>
    private let exportContinuation: AsyncStream<URL?>.Continuation

    /// Beyond this, the oldest half is dropped at a line boundary — newest evidence wins.
    private let byteLimit: Int

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()

    init(directory: URL? = nil, byteLimit: Int = 512 * 1024) {
        let directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = directory.appendingPathComponent("wire-log.jsonl")
        self.byteLimit = byteLimit
        (exportURLChanges, exportContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// The file once it holds anything — `nil` keeps a share affordance honest about
    /// there being nothing to share.
    nonisolated var exportURL: URL? {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > 0
        else { return nil }
        return fileURL
    }

    func append(_ entry: Entry) {
        guard var line = try? encoder.encode(entry) else { return }
        // An entry bigger than the whole bound would defeat it: swap in a stub —
        // the line says the exchange happened, the bound stays true (review, PR #33).
        if line.count + 1 > byteLimit {
            let stub = Entry(
                at: entry.at, operation: entry.operation, method: entry.method,
                path: entry.path, error: "entry exceeded the log bound"
            )
            guard let encoded = try? encoder.encode(stub), encoded.count + 1 <= byteLimit
            else { return }
            line = encoded
        }
        line.append(UInt8(ascii: "\n"))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try enforceLimit(appending: line.count)
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: fileURL)
            }
            // The file holds route PII — locked means locked (review, PR #33).
            // Writes only ever run while the app is up, i.e. unlocked.
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path
            )
            exportContinuation.yield(exportURL)
        } catch {
            // A diagnostics store that can't write is a shrug, not a failure — the
            // request it was watching already returned.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        exportContinuation.yield(exportURL)
    }

    /// Keeps the newest `byteLimit / 2` bytes, cut at a newline so the oldest kept line
    /// is whole. Runs only when an append would exceed the bound.
    private func enforceLimit(appending: Int) throws {
        guard let size = try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int,
            size + appending > byteLimit,
            let data = try? Data(contentsOf: fileURL)
        else { return }
        let suffix = data.suffix(byteLimit / 2)
        guard let newline = suffix.firstIndex(of: UInt8(ascii: "\n")) else { return }
        try Data(suffix.suffix(from: newline + 1)).write(to: fileURL)
    }
}
