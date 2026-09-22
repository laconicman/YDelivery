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
    /// there being nothing to share. A torn final line means bytes no process
    /// vouched for — possibly inherited from a previous launch — and they are
    /// never shareable (review, PR #33).
    nonisolated var exportURL: URL? {
        guard let data = try? Data(contentsOf: fileURL),
              data.last == UInt8(ascii: "\n")
        else { return nil }
        let body = data.dropLast()
        let lastLineStart = body.lastIndex(of: UInt8(ascii: "\n"))
            .map { body.index(after: $0) } ?? body.startIndex
        let lastLine = body.suffix(from: lastLineStart)
        guard let object = try? JSONSerialization.jsonObject(with: lastLine),
              object is [String: Any]
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
                // A torn tail is unvouched — possibly inherited from a previous
                // launch — so it is cut before anything new lands on it. The cut
                // can leave nothing vouched at all, in which case the create
                // path below takes over.
                try cutUnvouchedTail()
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try enforceLimit(appending: line.count)
                let handle = try FileHandle(forWritingTo: fileURL)
                let tail = try handle.seekToEnd()
                do {
                    try handle.write(contentsOf: line)
                    try handle.close()
                } catch {
                    // A truncated tail is a corrupt record — restore the cut. If
                    // even the rollback fails, drop the file: it holds bytes we
                    // can't vouch for (review, PR #33).
                    do {
                        try handle.truncate(atOffset: tail)
                        try handle.close()
                    } catch {
                        try? handle.close()
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    throw error
                }
            } else {
                do {
                    try line.write(to: fileURL, options: .atomic)
                    // The file holds route PII — locked means locked, and a file
                    // we cannot lock must not stay on disk at all. Protection is
                    // set once here; attributes persist across later appends
                    // (review, PR #33).
                    try FileManager.default.setAttributes(
                        [.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path
                    )
                } catch {
                    try? FileManager.default.removeItem(at: fileURL)
                    throw error
                }
            }
        } catch {
            // A diagnostics store that can't write is a shrug, not a failure — the
            // request it was watching already returned.
        }
        // Whatever happened above, `exportURL` reads the filesystem live and
        // refuses torn bytes — the published value is always the truth.
        exportContinuation.yield(exportURL)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        exportContinuation.yield(exportURL)
    }

    /// A file whose last byte isn't a newline ends in unvouched bytes — a write
    /// that never completed, maybe in a previous process. Truncate back past the
    /// last whole line; a file with no whole line at all is dropped entirely.
    private func cutUnvouchedTail() throws {
        let probe = try FileHandle(forReadingFrom: fileURL)
        guard let end = try? probe.seekToEnd(), end > 0 else { try? probe.close(); return }
        try probe.seek(toOffset: end - 1)
        let lastByte = try probe.read(upToCount: 1)?.first
        try probe.close()
        guard lastByte != UInt8(ascii: "\n") else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
        else {
            try FileManager.default.removeItem(at: fileURL)
            return
        }
        try data.prefix(through: lastNewline).write(to: fileURL, options: .atomic)
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
        try Data(suffix.suffix(from: newline + 1)).write(to: fileURL, options: .atomic)
    }
}
