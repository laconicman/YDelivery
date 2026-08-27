import Foundation
import Observation
import YandexDeliveryExpressAPI

/// The app's session: owns the OAuth token and the API client built from it.
///
/// Created once in `@main` and injected with `.environment(_:)` — never a singleton
/// (CLAUDE.md rule 2). Being unauthenticated is a state this type exposes for rendering,
/// not a crash (rule 3). Generated package types stop here: features receive what they
/// need through controllers, never `Components.Schemas.*` (rule 1).
@Observable @MainActor
final class ClientController {
    /// Non-nil exactly while signed in.
    private(set) var client: Client?

    /// The most recent sign-in failure, cleared by the next attempt or by signing out.
    private(set) var signInError: (any Error)?

    private let tokenStore: TokenStore

    /// Restores the previous session, if a token was stored.
    init(tokenStore: TokenStore = TokenStore()) {
        self.tokenStore = tokenStore
        if let token = tokenStore.read() { establishSession(token: token) }
    }

    var isSignedIn: Bool { client != nil }

    /// Screen-level derivation for the Settings form (R5: derivation lives here, not in a
    /// view's `body`).
    var signInErrorText: String? { signInError?.localizedDescription }

    /// The one validation this controller owns: an all-whitespace token is a mistake, not
    /// a credential. Everything else about token validity only the live API can say.
    struct EmptyTokenError: LocalizedError {
        var errorDescription: String? { String(localized: "The token is empty.") }
    }

    /// Persists the token, then builds the client from it. Failure of any step lands in
    /// ``signInError`` and leaves the controller signed out.
    func signIn(token: String) {
        signInError = nil
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            client = nil
            signInError = EmptyTokenError()
            return
        }
        do {
            try tokenStore.write(token)
            establishSession(token: token)
        } catch {
            client = nil
            signInError = error
        }
    }

    /// Forgets the token and the client. A Keychain delete failure still signs the session
    /// out, but surfaces as ``signInError`` — a credential the user asked to remove and
    /// could not be is worth rendering.
    func signOut() {
        client = nil
        signInError = nil
        do { try tokenStore.delete() } catch { signInError = error }
    }

    private func establishSession(token: String) {
        do {
            client = try Client(credentials: Credentials(authToken: token))
        } catch {
            client = nil
            signInError = error
        }
    }
}
