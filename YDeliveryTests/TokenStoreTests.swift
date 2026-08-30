import Foundation
import Security
import Testing
import YDeliveryKit
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

    @Test("The token lands in the App-Group access group — the transfer-proof one")
    func storedInAppGroupAccessGroup() throws {
        let store = makeStore()
        defer { try? store.delete() }
        try store.write("grouped")

        // Read the stored item's attributes back through raw SecItem, independent of the
        // store's own query, so a regression to the default (team-prefixed) group fails
        // here rather than after a future account transfer.
        let attributesQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        #expect(SecItemCopyMatching(attributesQuery as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessGroup as String] as? String == AppGroup.id)
    }
}
