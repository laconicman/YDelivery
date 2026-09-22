import Foundation
import Observation
import OSLog
import OSLogLoggingMiddleware
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

    /// The wire-evidence capture every session's client carries (Settings shares it).
    let wireLog: WireLogStore

    /// Settings' share affordance binds here — a live mirror of the log's
    /// shareability, gated on a live session: signed out means nothing is
    /// shareable even while a wiped file's removal is still in flight
    /// (review, PR #33).
    private(set) var diagnosticsURL: URL?

    /// The identity-boundary log wipe — owned, not floating, so rule 6's
    /// "structured and owned" holds even for best-effort housekeeping (review, PR #33).
    private var housekeeping: Task<Void, Never>?

    /// Mirrors the store's shareability stream into ``diagnosticsURL``.
    private var logObservation: Task<Void, Never>?

    /// Restores the previous session, if a token was stored.
    init(tokenStore: TokenStore = TokenStore(), wireLog: WireLogStore = WireLogStore()) {
        self.tokenStore = tokenStore
        self.wireLog = wireLog
        logObservation = Task { [weak self] in
            for await url in wireLog.exportURLChanges {
                self?.diagnosticsURL = self?.isSignedIn == true ? url : nil
            }
        }
        if let token = tokenStore.read() { establishSession(token: token) }
        diagnosticsURL = isSignedIn ? wireLog.exportURL : nil
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
    func signIn(token: String) async {
        signInError = nil
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            client = nil
            signInError = EmptyTokenError()
            return
        }
        do {
            try tokenStore.write(token)
            // A new credential means a new identity — the wipe completes before
            // the client exists, so the new session's first exchange can neither
            // land beside the previous identity's data nor be erased by its
            // removal. Session *restore* must not clear: surviving relaunch is
            // the file's whole point (review, PR #33).
            await wireLog.clear()
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
        // The share affordance goes dark now — the file itself is erased a hop
        // later, and the `isSignedIn` gate on ``diagnosticsURL`` keeps a late
        // in-flight write of this identity from ever looking shareable
        // (review, PR #33).
        diagnosticsURL = nil
        housekeeping = Task { await wireLog.clear() }
        do { try tokenStore.delete() } catch { signInError = error }
    }

    private func establishSession(token: String) {
        do {
            client = try Client(
                credentials: Credentials(authToken: token),
                // Two sinks on the same exchanges: console lines at .debug for an
                // attached debugger, and the bounded file Settings can share.
                middlewares: [
                    OSLogLoggingMiddleware(
                        logger: Logger(subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "wire"),
                        bodyLoggingConfiguration: .upTo(maxBytes: 32 * 1024)
                    ),
                    WireLogMiddleware(store: wireLog),
                ]
            )
        } catch {
            client = nil
            signInError = error
        }
    }
}
