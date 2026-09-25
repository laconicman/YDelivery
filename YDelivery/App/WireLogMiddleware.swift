import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Records each exchange into a ``WireLogStore`` — the evidence path for open wire
/// questions (TD-22's kind: what the API actually returned).
///
/// Runs after `AuthMiddleware`, so the request it sees carries `Authorization` — and the
/// store never records headers (TD-23). Bodies are captured only when their length is
/// known and within `bodyByteLimit`: collecting a stream consumes it, so an unknown or
/// oversized body passes through untouched with a marker rather than arriving truncated.
struct WireLogMiddleware: ClientMiddleware {
    let store: WireLogStore

    /// The store's write epoch, minted at init — this middleware's session generation.
    /// A `clear()` since then means a new identity owns the log and every entry stamped
    /// with this epoch drops at the gate, however late it lands (YD-18).
    let epoch: UInt64

    /// Bodies larger than this record `"<N bytes>"` instead of their contents.
    let bodyByteLimit: Int

    init(store: WireLogStore, bodyByteLimit: Int = 32 * 1024) {
        self.store = store
        self.epoch = store.writeEpoch
        self.bodyByteLimit = bodyByteLimit
    }

    nonisolated func intercept(
        _ request: HTTPRequest,
        body requestBody: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var entry = WireLogStore.Entry(
            at: .now,
            operation: operationID,
            method: request.method.rawValue,
            path: request.path ?? ""
        )
        let (requestNote, bodyForNext) = try await capture(requestBody)
        entry.requestBody = requestNote
        do {
            let (response, responseBody) = try await next(request, bodyForNext, baseURL)
            // The status is known the moment headers arrive — record it before the
            // body is collected, so a body that fails mid-stream still leaves its
            // status in the entry (review, PR #33).
            entry.status = response.status.code
            let (responseNote, bodyForCaller) = try await capture(responseBody)
            entry.responseBody = responseNote
            await store.append(entry, epoch: epoch)
            return (response, bodyForCaller)
        } catch {
            entry.error = error.localizedDescription
            await store.append(entry, epoch: epoch)
            throw error
        }
    }

    /// Reads a body for the log only when it can be put back whole.
    private nonisolated func capture(_ body: HTTPBody?) async throws -> (note: String?, body: HTTPBody?) {
        guard let body else { return (nil, nil) }
        switch body.length {
        case .unknown:
            return ("<unknown length>", body)
        case .known(let count) where count > bodyByteLimit:
            return ("<\(count) bytes>", body)
        case .known:
            let data = try await Data(collecting: body, upTo: bodyByteLimit)
            let note = String(data: data, encoding: .utf8) ?? "<non-UTF8 \(data.count) bytes>"
            return (note, HTTPBody(data))
        }
    }
}
