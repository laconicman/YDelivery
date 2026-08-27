import Foundation
import Testing
@testable import YDelivery

@Suite("Client controller session")
@MainActor
struct ClientControllerTests {
    private func makeStore(_ function: String = #function) -> TokenStore {
        TokenStore(service: "tests.YDelivery.\(function).\(UUID().uuidString)")
    }

    @Test("An empty store starts signed out, without an error")
    func startsSignedOut() {
        let controller = ClientController(tokenStore: makeStore())

        #expect(!controller.isSignedIn)
        #expect(controller.signInError == nil)
    }

    @Test("Signing in builds a client and persists the token")
    func signInPersists() throws {
        let store = makeStore()
        defer { try? store.delete() }
        let controller = ClientController(tokenStore: store)

        controller.signIn(token: "  y0_token-with-padding \n")

        #expect(controller.isSignedIn)
        #expect(controller.signInError == nil)
        #expect(store.read() == "y0_token-with-padding", "the token is trimmed before storage")
    }

    @Test("A stored token restores the session on init")
    func restoresSession() throws {
        let store = makeStore()
        defer { try? store.delete() }
        try store.write("y0_persisted")

        let controller = ClientController(tokenStore: store)

        #expect(controller.isSignedIn)
    }

    @Test("An all-whitespace token is refused as a rendered error, not a session")
    func refusesEmptyToken() {
        let controller = ClientController(tokenStore: makeStore())

        controller.signIn(token: "   \n")

        #expect(!controller.isSignedIn)
        #expect(controller.signInError is ClientController.EmptyTokenError)
        #expect(controller.signInErrorText != nil)
    }

    @Test("Signing out forgets the client and the stored token")
    func signOutForgets() throws {
        let store = makeStore()
        defer { try? store.delete() }
        let controller = ClientController(tokenStore: store)
        controller.signIn(token: "y0_short-lived")

        controller.signOut()

        #expect(!controller.isSignedIn)
        #expect(controller.signInError == nil)
        #expect(store.read() == nil)
    }
}
