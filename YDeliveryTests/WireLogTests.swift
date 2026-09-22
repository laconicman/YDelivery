import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import YDelivery

/// The capture store and the middleware that feeds it — the evidence path an engaged
/// user shares when the API answers something the spec didn't predict (TD-22's kind).
@Suite("Wire log")
struct WireLogTests {
    private func store() throws -> (WireLogStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WireLogStore(directory: directory)
        return (store, store.fileURL)
    }

    private func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    @Test("An appended entry is one JSONL line and becomes shareable")
    func appendWritesShareableLine() async throws {
        let (store, url) = try store()
        #expect(store.exportURL == nil, "an empty log is not shareable")

        await store.append(.init(at: .now, operation: "claims/cancel", method: "POST",
                                 path: "/claims/42/cancel", status: 200,
                                 responseBody: #"{"status":"cancelled"}"#))

        let lines = try lines(url)
        #expect(lines.count == 1)
        #expect(lines[0].contains(#""operation":"claims/cancel""#))
        #expect(lines[0].contains(#""status":200"#))
        #expect(store.exportURL == url)
    }

    @Test("Past the bound, the oldest half is dropped at a line boundary")
    func boundDropsOldestHalf() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WireLogStore(directory: directory, byteLimit: 200)

        for i in 0..<8 {
            await store.append(.init(at: .now, operation: "op-\(i)", method: "GET",
                                     path: "/x", status: 200))
        }

        let kept = try lines(store.fileURL)
        #expect(kept.allSatisfy { $0.hasPrefix("{") },
                "every kept line must be whole — a partial first line is a corrupt record")
        #expect(kept.last?.contains(#""operation":"op-7""#) == true)
        #expect(kept.count < 8, "the bound must actually drop entries")
    }

    @Test("The middleware records status and both bodies, never headers")
    func middlewareCapturesExchange() async throws {
        let (store, url) = try store()
        let middleware = WireLogMiddleware(store: store)
        let request = HTTPRequest(method: .post, scheme: "https", authority: "x", path: "/claims/42/cancel")
        let response = HTTPResponse(status: .ok)

        _ = try await middleware.intercept(
            request, body: HTTPBody(Data(#"{"cancel_state":"free"}"#.utf8)), baseURL: URL(string: "https://x")!,
            operationID: "claims/cancel"
        ) { _, _, _ in (response, HTTPBody(Data(#"{"status":"new"}"#.utf8))) }

        let line = try #require(try lines(url).first)
        #expect(line.contains(#""responseBody":"{\"status\":\"new\"}"#))
        #expect(line.contains(#""requestBody":"{\"cancel_state\":\"free\"}"#))
        #expect(!line.contains("uthorization"), "TD-23: headers never reach the log")
    }

    @Test("An oversized body passes through whole and records a marker")
    func oversizedBodyPassesThrough() async throws {
        let (store, url) = try store()
        let middleware = WireLogMiddleware(store: store, bodyByteLimit: 8)
        let request = HTTPRequest(method: .post, scheme: "https", authority: "x", path: "/x")
        let big = String(repeating: "x", count: 100)

        let (response, passedBody) = try await middleware.intercept(
            request, body: HTTPBody(Data(big.utf8)), baseURL: URL(string: "https://x")!,
            operationID: "op"
        ) { _, forwarded, _ in
            // The caller's body must arrive intact — a truncated forward corrupts the request.
            let received = try await Data(collecting: forwarded!, upTo: 1024)
            #expect(String(data: received, encoding: .utf8) == big)
            return (HTTPResponse(status: .ok), nil)
        }
        _ = response
        _ = passedBody

        let line = try #require(try lines(url).first)
        #expect(line.contains("<100 bytes>"), "the marker says the bound, not a guess at content")
    }

    @Test("A thrown next still records the exchange, with the error")
    func failureIsRecorded() async throws {
        let (store, url) = try store()
        let middleware = WireLogMiddleware(store: store)
        let request = HTTPRequest(method: .get, scheme: "https", authority: "x", path: "/x")

        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await middleware.intercept(
                request, body: nil, baseURL: URL(string: "https://x")!, operationID: "op"
            ) { _, _, _ in throw Boom() }
        }

        let line = try #require(try lines(url).first)
        #expect(line.contains(#""error""#))
        #expect(line.contains(#""status""#) == false)
    }

    @Test("A body that dies mid-stream still leaves the status it arrived with")
    func failedBodyKeepsStatus() async throws {
        let (store, url) = try store()
        let middleware = WireLogMiddleware(store: store)
        let request = HTTPRequest(method: .get, scheme: "https", authority: "x", path: "/x")

        struct CutShort: Error {}
        let stream = AsyncThrowingStream<HTTPBody.ByteChunk, Error> { continuation in
            continuation.yield([UInt8(ascii: "{")])
            continuation.finish(throwing: CutShort())
        }
        let body = HTTPBody(stream, length: .known(100))

        await #expect(throws: CutShort.self) {
            try await middleware.intercept(
                request, body: nil, baseURL: URL(string: "https://x")!, operationID: "op"
            ) { _, _, _ in (HTTPResponse(status: .badGateway), body) }
        }

        let line = try #require(try lines(url).first)
        #expect(line.contains(#""status":502"#), "headers arrived — the status is evidence too")
        #expect(line.contains(#""error""#))
    }

    @Test("An entry bigger than the whole bound lands as a stub, still bounded")
    func oversizedEntryBecomesStub() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WireLogStore(directory: directory, byteLimit: 200)

        await store.append(.init(
            at: .now, operation: "op", method: "POST", path: "/x",
            responseBody: String(repeating: "x", count: 500)
        ))

        let size = try FileManager.default
            .attributesOfItem(atPath: store.fileURL.path)[.size] as? Int
        #expect(size ?? .max <= 200, "a first entry must not open the file oversized")
        let line = try #require(try lines(store.fileURL).first)
        #expect(line.hasPrefix("{"), "the stub is still a whole JSON line")
        #expect(line.contains("exceeded the log bound"))
    }
}
