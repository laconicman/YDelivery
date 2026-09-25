import Foundation
import Observation
import OSLog
import OSLogLoggingMiddleware
import OpenAPIURLSession
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

    /// One synchronous call per identity transition — sign-in, sign-out, token
    /// swap — set once by the composition root. Anything bound to an account but
    /// sampled on a poll (the claims sync's cursor and flags) hangs its wipe here:
    /// a 30-second tick cannot see a sign-out that ends before the next tick
    /// (review, PR #35). Session *restore* at launch does not fire it — restoring
    /// is not a change.
    @ObservationIgnored var onIdentityChange: (@MainActor () -> Void)?

    /// The identity-boundary log wipe — owned, not floating, so rule 6's
    /// "structured and owned" holds even for best-effort housekeeping (review, PR #33).
    private var housekeeping: Task<Void, Never>?

    /// Mirrors the store's shareability stream into ``diagnosticsURL``.
    private var logObservation: Task<Void, Never>?

    /// The `URLSession` the current client's transport rides on. Owned so a rebuild
    /// or sign-out can invalidate it — unlike `client`, nil-ing it wouldn't cancel a
    /// connection pool the previous identity opened (YD-14's session is the app's
    /// second per-identity resource).
    private var providerURLSession: URLSession?

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
            dropSession()
            signInError = EmptyTokenError()
            return
        }
        do {
            try tokenStore.write(token)
            // Kill the old session before the wipe — a task in flight can still
            // append its (body-carrying) record through the wiped point
            // afterwards; invalidating first turns every pending response into
            // an error so nothing old-identity can arrive behind the new log
            // (review, PR #49). A cancelled task's error append can still race
            // the wipe — closing that needs a write epoch, see YD-18.
            providerURLSession?.invalidateAndCancel()
            // A new credential means a new identity — the wipe completes before
            // the client exists, so the new session's first exchange can neither
            // land beside the previous identity's data nor be erased by its
            // removal. Session *restore* must not clear: surviving relaunch is
            // the file's whole point (review, PR #33).
            await wireLog.clear()
            onIdentityChange?()
            establishSession(token: token)
        } catch {
            dropSession()
            signInError = error
        }
    }

    /// Forgets the token and the client. A Keychain delete failure still signs the session
    /// out, but surfaces as ``signInError`` — a credential the user asked to remove and
    /// could not be is worth rendering.
    func signOut() {
        dropSession()
        signInError = nil
        // The share affordance goes dark now — the file itself is erased a hop
        // later, and the `isSignedIn` gate on ``diagnosticsURL`` keeps a late
        // in-flight write of this identity from ever looking shareable
        // (review, PR #33).
        diagnosticsURL = nil
        housekeeping = Task { await wireLog.clear() }
        onIdentityChange?()
        do { try tokenStore.delete() } catch { signInError = error }
    }

    /// The provider's burst-load failure is a silent stall — no status, no
    /// `Retry-After`, connections held for 25+ minutes (YD-14) — so the request
    /// timeout is the whole budget a stalled request spends. Half the URLSession
    /// default, generous against the small JSON bodies these calls exchange.
    static let providerRequestTimeout: TimeInterval = 30

    /// `.default` rather than `.ephemeral` — the transport's own default session
    /// carries the same disk cache and credential semantics; only the timeouts change.
    static func providerSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = providerRequestTimeout
        // The request timeout bounds *idle* time — each arriving byte resets it.
        // The resource timeout is the wall-clock ceiling a drip-feeding stall
        // cannot reset (review, PR #49).
        configuration.timeoutIntervalForResource = 2 * providerRequestTimeout
        return URLSession(configuration: configuration)
    }

    /// Both per-identity resources die together — a `client = nil` that leaves the
    /// session open lets a previous identity's in-flight requests run out the clock.
    private func dropSession() {
        providerURLSession?.invalidateAndCancel()
        providerURLSession = nil
        client = nil
    }

    private func establishSession(token: String) {
        // Rebuild means re-own: the old session closes before the new one exists, so
        // no request or connection pool outlives the identity that opened it.
        providerURLSession?.invalidateAndCancel()
        let session = Self.providerSession()
        providerURLSession = session
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
                ],
                transport: URLSessionTransport(configuration: .init(session: session))
            )
        } catch {
            dropSession()
            signInError = error
        }
    }
}
