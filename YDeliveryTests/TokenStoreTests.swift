import Foundation
import Testing
@testable import YDelivery

/// Runs against the real Keychain in the test host, each test under its own service name so
/// parallel tests never see each other's items and the app's actual credential is never
/// touched.
@Suite("Token store")
struct TokenStoreTests {
    private func makeStore(_ function: String = #function) -> TokenStore {
        TokenStore(service: "tests.YDelivery.\(function).\(UUID().uuidString)")
    }

    @Test("A written token reads back verbatim")
    func roundTrip() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.write("y0_AgAAAAB-example")
        #expect(store.read() == "y0_AgAAAAB-example")
    }

    @Test("Writing replaces the previous token rather than accumulating")
    func writeReplaces() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.write("first")
        try store.write("second")
        #expect(store.read() == "second")
    }

    @Test("An empty store reads nil, and deleting it succeeds")
    func absentIsNilAndDeletable() throws {
        let store = makeStore()

        #expect(store.read() == nil)
        try store.delete()
    }

    @Test("Deleting removes the token")
    func deleteRemoves() throws {
        let store = makeStore()

        try store.write("doomed")
        try store.delete()
        #expect(store.read() == nil)
    }
}
