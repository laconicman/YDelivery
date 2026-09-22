import SwiftUI
import YDeliveryKit

/// Root view of one remembered order: what it is, and — while the claim is still
/// cancellable — what closing it would cost, asked live. The cancel surface exists so
/// a placed order can be walked back without paying for the lesson (author's ask,
/// 2026-09-22: "a cancelling claim screen, so I could play with the production server
/// without paying for delivery").
struct OrderDetailView: View {
    let order: Order
    @Environment(ClientController.self) private var session
    @Environment(StoreController.self) private var store
    @State private var model = Model()

    var body: some View {
        Content(
            order: order,
            cancellation: model.cancellation,
            retry: retryCancellation,
            confirm: { model.confirm(using: cancel) }
        )
        .navigationTitle(Text("Order"))
        .onAppear {
            if order.isCancellable { model.load(using: loadCancellation) }
        }
        .onDisappear { model.stop() }
    }

    /// "Try again" is whatever the current state needs — re-asking terms after a
    /// refusal, re-reading the claim after an accepted cancellation, re-writing
    /// history after the wire said cancelled but the disk didn't (review, PR #32).
    private func retryCancellation() {
        switch model.cancellation {
        case .unconfirmed: model.recheck(using: recheckCancellation)
        case .unrecorded: model.retryRecording(using: recordCancelled)
        default: model.load(using: loadCancellation)
        }
    }

    /// Both reads live behind the claim id — absent it, there is nothing to ask.
    /// A claim that already stands cancelled is reconciled into history on the way
    /// back — by this screen earlier, by support, anywhere — so leaving mid-confirm
    /// cannot strand an accepted cancellation between the wire and local memory
    /// (review, PR #32).
    private func loadCancellation() async throws -> ClaimCancellation {
        guard let id = order.claimID else { throw OffersUnavailable() }
        let asked = try await session.claimCancellation(id: id)
        if asked.status.isCancelled { try await recordCancelled() }
        return asked
    }

    /// Cancels, then writes the cancelled order into history — the store upserts
    /// by id, so history keeps one row that now says cancelled.
    private func cancel(_ cancellation: ClaimCancellation) async throws {
        guard let id = order.claimID else { return }
        _ = try await session.cancelClaim(
            id: id, version: cancellation.version, terms: cancellation.terms
        )
        try await recordCancelled()
    }

    /// The accepted-but-unproven retry: re-read the claim — its own status is the
    /// only word on whether the cancellation took. Never re-sends the mutation.
    private func recheckCancellation() async throws {
        guard let id = order.claimID else { return }
        _ = try await session.cancelledClaimState(id: id)
        try await recordCancelled()
    }

    /// The cancelled order into local history. A write failure here is the wire's
    /// success and the disk's failure — reported as itself, so the retry writes
    /// again rather than cancelling again (review, PR #32).
    private func recordCancelled() async throws {
        var updated = order
        updated.status = .cancelled
        do {
            try await store.record(updated)
        } catch {
            throw CancellationUnrecorded(error)
        }
    }
}

extension OrderDetailView {
    /// The cancellation ask's state machine — the screen's only moving part. History
    /// is the caller's: the model reports the answer; the root view records it.
    @Observable @MainActor
    final class Model {
        private(set) var cancellation: Cancellation = .loading
        /// The in-flight work — owned so it can be cancelled when the screen goes
        /// away, per rule 6 (review, PR #32). Each verb supersedes the last.
        private var task: Task<Void, Never>?
        /// Whether the in-flight task carries an accepted side effect. Loads may
        /// be abandoned with the screen; work past the provider's answer — the
        /// cancel, the confirming re-read, the history write — may not: dropping
        /// it strands a paid cancellation between the wire's truth and history's
        /// memory (review, PR #32).
        private var taskIsReconciliation = false

        enum Cancellation: Hashable {
            /// Asking the provider what cancelling costs.
            case loading
            /// Terms in hand — free, priced, or refused by the wire's own rules.
            case ready(ClaimCancellation)
            /// The ask or the mutation was refused; retrying re-asks.
            case failed(String)
            /// Confirmed, in flight.
            case cancelling
            /// The provider accepted the cancellation, but the claim's cancelled
            /// standing was never observed. Retrying re-reads the claim — never
            /// re-sends the mutation (review, PR #32).
            case unconfirmed(String)
            /// The claim stands cancelled but history's write failed. Retrying
            /// re-writes the row — the wire is not asked again (review, PR #32).
            case unrecorded(String)
            /// The provider said cancelled — terminal.
            case cancelled
        }

        @discardableResult
        func load(using fetch: @escaping () async throws -> ClaimCancellation) -> Task<Void, Never>? {
            // Never supersede work past the provider's answer — it owns the state
            // until it lands its side effect.
            guard !taskIsReconciliation else { return nil }
            task?.cancel()
            let next = Task {
                cancellation = .loading
                do {
                    let asked = try await fetch()
                    if !Task.isCancelled {
                        // A claim already cancelled — by this screen earlier, by
                        // support, anywhere — is resolved, not a terms question.
                        cancellation = asked.status.isCancelled ? .cancelled : .ready(asked)
                    }
                } catch let error as CancellationUnrecorded {
                    if !Task.isCancelled { cancellation = .unrecorded(Self.sentence(for: error)) }
                } catch {
                    if !Task.isCancelled { cancellation = .failed(Self.sentence(for: error)) }
                }
            }
            task = next
            return next
        }

        /// The confirm button's whole job — refuses to fire unless terms are in hand
        /// and consentable: a `paid` answer that never named its amount is not a
        /// price anyone can agree to (review, PR #32).
        @discardableResult
        func confirm(
            using cancel: @escaping (ClaimCancellation) async throws -> Void
        ) -> Task<Void, Never>? {
            guard case .ready(let current) = cancellation,
                  current.terms.isConfirmable
            else { return nil }
            task?.cancel()
            taskIsReconciliation = true
            let next = Task {
                defer { taskIsReconciliation = false }
                cancellation = .cancelling
                do {
                    try await cancel(current)
                    if !Task.isCancelled { cancellation = .cancelled }
                } catch let error as CancellationUnrecorded {
                    if !Task.isCancelled { cancellation = .unrecorded(Self.sentence(for: error)) }
                } catch let error as CancellationUnconfirmed {
                    if !Task.isCancelled { cancellation = .unconfirmed(Self.sentence(for: error)) }
                } catch {
                    if !Task.isCancelled { cancellation = .failed(Self.sentence(for: error)) }
                }
            }
            task = next
            return next
        }

        /// The unconfirmed retry — re-read the claim's own status; the accepted
        /// mutation is never sent twice.
        @discardableResult
        func recheck(using recheck: @escaping () async throws -> Void) -> Task<Void, Never>? {
            guard case .unconfirmed = cancellation else { return nil }
            task?.cancel()
            taskIsReconciliation = true
            let next = Task {
                defer { taskIsReconciliation = false }
                do {
                    try await recheck()
                    if !Task.isCancelled { cancellation = .cancelled }
                } catch let error as CancellationUnrecorded {
                    if !Task.isCancelled { cancellation = .unrecorded(Self.sentence(for: error)) }
                } catch {
                    if !Task.isCancelled { cancellation = .unconfirmed(Self.sentence(for: error)) }
                }
            }
            task = next
            return next
        }

        /// The unrecorded retry — re-write the cancelled order to history; the
        /// wire already said its word.
        @discardableResult
        func retryRecording(using record: @escaping () async throws -> Void) -> Task<Void, Never>? {
            guard case .unrecorded = cancellation else { return nil }
            task?.cancel()
            taskIsReconciliation = true
            let next = Task {
                defer { taskIsReconciliation = false }
                do {
                    try await record()
                    if !Task.isCancelled { cancellation = .cancelled }
                } catch {
                    if !Task.isCancelled { cancellation = .unrecorded(Self.sentence(for: error)) }
                }
            }
            task = next
            return next
        }

        /// The screen went away — pre-mutation work ends with it (rule 6). Work
        /// past the provider's answer runs to the end instead: abandoning an
        /// accepted cancellation's re-read or history write strands a paid
        /// cancellation between the wire's truth and history's memory (PR #32).
        func stop() {
            guard !taskIsReconciliation else { return }
            task?.cancel()
            task = nil
        }

        private static func sentence(for error: any Error) -> String {
            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("Searching — cancellable") {
    NavigationStack {
        OrderDetailView(order: .previewSearching)
            .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
            .environment(StoreController(orderStore: nil, placeStore: nil))
    }
}

#Preview("Done — terminal") {
    NavigationStack {
        OrderDetailView(order: .previewDone)
            .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
            .environment(StoreController(orderStore: nil, placeStore: nil))
    }
}
