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
}
