import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The deep-link grammar (board `5b`/`5d`) — what the widget, the Live
/// Activity and the App Intents are allowed to ask for. The parser is the
/// contract: a link that doesn't parse must degrade to "no link", never to a
/// half-opened screen.
@Suite("DeepLink parsing")
struct DeepLinkTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    @Test("The grammar's four sentences parse")
    func grammarParses() throws {
        #expect(DeepLink(url: URL(string: "ydelivery://order/\(id.uuidString)")!)
                == .order(id))
        #expect(DeepLink(url: URL(string: "ydelivery://compose")!) == .compose)
        #expect(DeepLink(url: URL(string: "ydelivery://repeat?order=\(id.uuidString)")!)
                == .repeatOrder(id))
        #expect(DeepLink(url: URL(string: "ydelivery://repeat?place=\(id.uuidString)")!)
                == .repeatPlace(id))
    }

    @Test("What the widget writes is what the app parses")
    func buildersRoundTrip() throws {
        #expect(DeepLink(url: DeepLink.order(id)) == .order(id))
        #expect(DeepLink(url: DeepLink.repeatOrder(id)) == .repeatOrder(id))
        #expect(DeepLink(url: DeepLink.repeatPlace(id)) == .repeatPlace(id))
    }

    @Test("A malformed or foreign link is no link at all")
    func malformedIsNil() {
        #expect(DeepLink(url: URL(string: "https://order/\(id.uuidString)")!) == nil,
                "another scheme answers nothing")
        #expect(DeepLink(url: URL(string: "ydelivery://order/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "ydelivery://repeat")!) == nil,
                "repeat with no operand asks for nothing")
        #expect(DeepLink(url: URL(string: "ydelivery://cancel?order=\(id.uuidString)")!) == nil,
                "verbs outside the grammar parse to nil — a link never acts")
        #expect(DeepLink(url: URL(string: "ydelivery://repeat?place=zzz")!) == nil)
    }
}
