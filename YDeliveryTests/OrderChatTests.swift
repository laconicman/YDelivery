import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The chat screen's model — the stream's read lifecycle, the post-then-reload
/// contract, and the lazy photo fetch. Wire/store concerns stay out: the verbs
/// take closures, so the seam itself is what PersistenceTests already proves.
@Suite("The order's chat")
@MainActor
struct OrderChatTests {
    private let orderID = UUID()

    @Test("A read publishes the stream, oldest first")
    func loadPublishes() async {
        let model = OrderChatView.Model()
        let fixture = [OrderMessage(orderID: orderID, kind: OrderMessage.Kind.text, text: "hi")]
        await model.load { fixture }
        #expect(model.messages == fixture)
        #expect(model.loadError == nil)
    }

    @Test("A failed read says so — nil stays 'asking', never 'empty'")
    func loadFailureKeepsAsking() async {
        let model = OrderChatView.Model()
        await model.load { throw StoreController.StoreUnavailable() }
        #expect(model.messages == nil)
        #expect(model.loadError != nil)
    }

    @Test("A landed post re-reads the stream — the row arrives in its seat")
    func postReloads() async {
        let model = OrderChatView.Model()
        var stream: [OrderMessage] = []
        let message = OrderMessage(orderID: orderID, kind: OrderMessage.Kind.text, text: "привет")
        let sent = await model.post(message, using: { stream.append($0) }, then: { stream })
        #expect(sent)
        #expect(model.messages == [message])
        #expect(model.sendError == nil)
        #expect(!model.isSending)
    }

    @Test("A refused post keeps the draft — and the stream untouched")
    func postFailureKeepsDraft() async {
        let model = OrderChatView.Model()
        let sent = await model.post(
            OrderMessage(orderID: orderID, kind: OrderMessage.Kind.text, text: "hi"),
            using: { _ in throw StoreController.StoreUnavailable() },
            then: { [] })
        #expect(!sent)
        #expect(model.sendError != nil)
        #expect(model.messages == nil, "a failed post fabricates no stream")
    }

    @Test("A photo's bytes arrive once, by id — a miss leaves the frame empty")
    func photoFetchesByID() async {
        let model = OrderChatView.Model()
        let id = UUID()
        var asks = 0
        model.photo(id) { _ in asks += 1; return Data([7]) }
        model.photo(id) { _ in asks += 1; return Data([7]) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.photoData[id] == Data([7]))
        #expect(asks == 1, "the row re-asks every render; the fetch must not repeat")
    }

    @Test("A landed post whose re-read failed still counts — retrying must not duplicate")
    func postSurvivesFailedReload() async {
        let model = OrderChatView.Model()
        var posted: OrderMessage?
        let sent = await model.post(
            OrderMessage(orderID: orderID, kind: OrderMessage.Kind.text, text: "hi"),
            using: { posted = $0 },
            then: { throw StoreController.StoreUnavailable() })
        #expect(sent, "the write landed — the draft is spent")
        #expect(posted != nil)
        #expect(model.sendError == nil, "nothing failed at the write door")
        #expect(model.loadError != nil, "the stale stream says so instead")
    }

    @Test("A superseded read cannot overwrite a post's fresher stream")
    func staleLoadCannotOverwritePost() async {
        let model = OrderChatView.Model()
        let gate = StreamGate()
        let stale = OrderMessage(orderID: orderID, kind: OrderMessage.Kind.text, text: "stale")
        let fresh = OrderMessage(orderID: orderID, kind: OrderMessage.Kind.text, text: "fresh")
        let loadTask = Task { await model.load { await gate.wait() } }
        while !gate.entered { await Task.yield() }
        let sent = await model.post(fresh, using: { _ in }, then: { [fresh] })
        gate.resume(with: [stale])
        await loadTask.value
        #expect(sent)
        #expect(model.messages == [fresh], "the older snapshot must not land over the post's")
    }

    @Test("A stream reload re-asks for photos still missing bytes")
    func loadReasksMissingPhotos() async {
        let model = OrderChatView.Model()
        let ref = UUID()
        let counter = Counter()
        model.photo(ref) { _ in
            counter.n += 1
            return counter.n >= 2 ? Data([1]) : nil
        }
        while model.photoRequests.contains(ref) { await Task.yield() }
        #expect(model.photoData[ref] == nil)
        let photoMessage = OrderMessage(
            orderID: orderID, kind: OrderMessage.Kind.photo, attachmentRef: ref)
        await model.load { [photoMessage] }
        for _ in 0..<50 where model.photoData[ref] == nil { await Task.yield() }
        #expect(counter.n == 2, "the placeholder's next ask rides the reload")
        #expect(model.photoData[ref] == Data([1]))
    }

    /// A suspended stream read — `wait` parks on the gate, `resume` releases it.
    private final class StreamGate: @unchecked Sendable {
        private(set) var entered = false
        private var waiter: CheckedContinuation<[OrderMessage], Never>?
        func wait() async -> [OrderMessage] {
            entered = true
            return await withCheckedContinuation { waiter = $0 }
        }
        func resume(with value: [OrderMessage]) { waiter?.resume(returning: value) }
    }

    private final class Counter: @unchecked Sendable { var n = 0 }
}
