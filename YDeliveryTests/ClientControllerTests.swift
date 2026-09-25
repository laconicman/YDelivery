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
    func signInPersists() async throws {
        let store = makeStore()
        defer { try? store.delete() }
        let controller = ClientController(tokenStore: store)

        await controller.signIn(token: "  y0_token-with-padding \n")

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
    func refusesEmptyToken() async {
        let controller = ClientController(tokenStore: makeStore())

        await controller.signIn(token: "   \n")

        #expect(!controller.isSignedIn)
        #expect(controller.signInError is ClientController.EmptyTokenError)
        #expect(controller.signInErrorText != nil)
    }

    @Test("Signing out forgets the client and the stored token")
    func signOutForgets() async throws {
        let store = makeStore()
        defer { try? store.delete() }
        let controller = ClientController(tokenStore: store)
        await controller.signIn(token: "y0_short-lived")

        controller.signOut()

        #expect(!controller.isSignedIn)
        #expect(controller.signInError == nil)
        #expect(store.read() == nil)
    }

    @Test("A fresh sign-in wipes the previous identity's log before the client exists")
    func signInWipesLogFirst() async throws {
        let store = makeStore()
        defer { try? store.delete() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let log = WireLogStore(directory: directory)
        await log.append(.init(at: .now, operation: "op", method: "GET", path: "/x",
                               status: 200, responseBody: #"{"of":"another-identity"}"#))
        let controller = ClientController(tokenStore: store, wireLog: log)

        await controller.signIn(token: "y0_new-identity")

        #expect(controller.isSignedIn)
        #expect(log.exportURL == nil, "the wipe precedes the session — no interleaving")
    }

    @Test("The share affordance follows the log and dies with the session")
    func diagnosticsFollowsIdentity() async throws {
        let store = makeStore()
        defer { try? store.delete() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let log = WireLogStore(directory: directory)
        let controller = ClientController(tokenStore: store, wireLog: log)
        await controller.signIn(token: "y0_x")

        await log.append(.init(at: .now, operation: "op", method: "GET", path: "/x",
                               status: 200))
        for _ in 0..<100 where controller.diagnosticsURL == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.diagnosticsURL == log.fileURL,
                "an appended exchange becomes shareable without leaving Settings")

        controller.signOut()
        #expect(controller.diagnosticsURL == nil,
                "the affordance goes dark synchronously — the wiped file can't be shared")
    }

    @Test("The provider session carries a tighter timeout than the 60 s transport default")
    func providerSessionTimeout() {
        // YD-14: under burst load the provider stalls connections silently, so this
        // timeout is the whole budget such a request spends. If it ever regresses to
        // the URLSession default the register entry is right back open.
        let session = ClientController.providerSession()

        #expect(session.configuration.timeoutIntervalForRequest == ClientController.providerRequestTimeout)
        #expect(ClientController.providerRequestTimeout < 60)
    }

    @Test("A drip-feed stall cannot outrun the request timeout — the resource bound")
    func providerSessionResourceTimeout() {
        // `timeoutIntervalForRequest` resets on every arriving byte; only the
        // resource timeout is wall-clock. Pin that both exist (review, PR #49).
        let session = ClientController.providerSession()

        #expect(session.configuration.timeoutIntervalForResource
                == 2 * ClientController.providerRequestTimeout)
    }
}
