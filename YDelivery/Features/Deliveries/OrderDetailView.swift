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
            fields: store.fields(for: order.id),
            cancellation: model.cancellation,
            reconciling: model.isReconciling,
            retry: retryCancellation,
            confirm: { model.confirm(using: cancel) }
        )
        .navigationTitle(Text("Order"))
        .onAppear {
            if order.isCancellable {
                model.load(using: loadCancellation, onTerminal: recordCancelled)
            }
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
        default: model.load(using: loadCancellation, onTerminal: recordCancelled)
        }
    }

    /// Both reads live behind the claim id — absent it, there is nothing to ask.
    /// A claim that already stands cancelled is reconciled into history by the
    /// model's `onTerminal` — by this screen earlier, by support, anywhere — so
    /// leaving mid-confirm cannot strand an accepted cancellation between the
    /// wire and local memory (review, PR #32).
    private func loadCancellation() async throws -> ClaimCancellation {
        guard let id = order.claimID else { throw OffersUnavailable() }
        return try await session.claimCancellation(id: id)
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

    /// The unknown-outcome retry: re-read the claim — its own status is the only
    /// word on whether the cancellation took, and it never re-sends the mutation.
    /// Cancelled lands the history write; still standing means the mutation never
    /// applied, so the screen goes back to fresh terms and an explicit confirm —
    /// never an automatic resend (review, PR #32).
    private func recheckCancellation() async throws -> Model.Cancellation {
        guard let id = order.claimID else { throw OffersUnavailable() }
        let standing = try await session.claimState(id: id)
        if standing.status.isCancelled {
            try await recordCancelled()
            return .cancelled
        }
        let refreshed = try await loadCancellation()
        guard !refreshed.status.isCancelled else {
            try await recordCancelled()
            return .cancelled
        }
        return .ready(refreshed)
    }

    /// The cancelled order into local history. A write failure here is the wire's
    /// success and the disk's failure — reported as itself, so the retry writes
    /// again rather than cancelling again (review, PR #32).
    private func recordCancelled() async throws {
        var updated = order
        updated.status = .cancelled
        do {
            try await store.record(updated, providerObservedAt: .now)
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
        /// Terms reads — owned so the screen going away can cancel them (rule 6,
        /// review PR #32). Each load supersedes the last.
        private var inquiry: Task<Void, Never>?
        /// Work past the provider's answer — the cancel, the confirming re-read,
        /// the history write. Single-flight by construction: non-nil exactly
        /// while one runs, never superseded, and `stop()` never touches it —
        /// abandoning it strands a paid cancellation between the wire's truth
        /// and history's memory (review, PR #32).
        private var reconciliation: Task<Cancellation, Never>?
        /// Load lineage — a superseded read must not clear its successor's slot.
        private var generation = 0

        /// Whether post-answer work is in flight — the screen uses it to keep a
        /// live retry from being tapped a second time (review, PR #32).
        var isReconciling: Bool { reconciliation != nil }

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

        /// Installs post-answer work as the single reconciliation task: every
        /// verb refuses while `reconciliation` is non-nil, so the task is never
        /// superseded and clears its own slot. The task sets `cancellation`
        /// itself — it reports the outcome even when the caller that awaited it
        /// (an escalated load, a dismissed screen) is already gone.
        private func reconcile(
            using work: @escaping () async -> Cancellation
        ) -> Task<Cancellation, Never> {
            let next = Task {
                defer { reconciliation = nil }
                let outcome = await work()
                cancellation = outcome
                return outcome
            }
            reconciliation = next
            return next
        }

        /// `onTerminal` runs only if the fresh read finds the claim already
        /// cancelled — as reconciliation work, so a `stop()` that kills this
        /// load cannot strand the history write (review, PR #32).
        @discardableResult
        func load(
            using fetch: @escaping () async throws -> ClaimCancellation,
            onTerminal: @escaping () async throws -> Void = {}
        ) -> Task<Void, Never>? {
            // Never run beside work past the provider's answer — it owns the
            // state until it lands its side effect.
            guard reconciliation == nil else { return nil }
            generation += 1
            let born = generation
            inquiry?.cancel()
            let next = Task {
                defer { if generation == born { inquiry = nil } }
                cancellation = .loading
                do {
                    let asked = try await fetch()
                    guard !Task.isCancelled else { return }
                    if asked.status.isCancelled {
                        // A claim already cancelled — by this screen earlier, by
                        // support, anywhere — is resolved, not a terms question.
                        // The history write is reconciliation work: a fresh task
                        // that survives this load's cancellation, and whose
                        // outcome is this screen's state.
                        cancellation = await reconcile(using: {
                            do {
                                try await onTerminal()
                                return .cancelled
                            } catch {
                                return .unrecorded(Self.sentence(for: error))
                            }
                        }).value
                    } else {
                        cancellation = .ready(asked)
                    }
                } catch let error as CancellationUnrecorded {
                    if !Task.isCancelled { cancellation = .unrecorded(Self.sentence(for: error)) }
                } catch {
                    if !Task.isCancelled { cancellation = .failed(Self.sentence(for: error)) }
                }
            }
            inquiry = next
            return next
        }

        /// The confirm button's whole job — refuses to fire unless terms are in hand
        /// and consentable: a `paid` answer that never named its amount is not a
        /// price anyone can agree to (review, PR #32).
        @discardableResult
        func confirm(
            using cancel: @escaping (ClaimCancellation) async throws -> Void
        ) -> Task<Cancellation, Never>? {
            guard reconciliation == nil,
                  case .ready(let current) = cancellation,
                  current.terms.isConfirmable
            else { return nil }
            inquiry?.cancel()
            return reconcile(using: {
                self.cancellation = .cancelling
                do {
                    try await cancel(current)
                    return .cancelled
                } catch let error as CancellationUnrecorded {
                    return .unrecorded(Self.sentence(for: error))
                } catch let error as CancellationUnconfirmed {
                    return .unconfirmed(Self.sentence(for: error))
                } catch {
                    return .failed(Self.sentence(for: error))
                }
            })
        }

        /// The unconfirmed retry — re-read the claim's own status; the accepted
        /// mutation is never sent twice. A second tap while one is in flight is
        /// refused, not queued — retrying already-running work can only race it.
        /// The read's answer decides the next state: cancelled, fresh terms when
        /// the claim still stands, or unconfirmed again when the read failed.
        @discardableResult
        func recheck(
            using recheck: @escaping () async throws -> Cancellation
        ) -> Task<Cancellation, Never>? {
            guard reconciliation == nil, case .unconfirmed = cancellation else { return nil }
            inquiry?.cancel()
            return reconcile(using: {
                do {
                    return try await recheck()
                } catch let error as CancellationUnrecorded {
                    return .unrecorded(Self.sentence(for: error))
                } catch {
                    return .unconfirmed(Self.sentence(for: error))
                }
            })
        }

        /// The unrecorded retry — re-write the cancelled order to history; the
        /// wire already said its word. Same refusal while one is in flight.
        @discardableResult
        func retryRecording(using record: @escaping () async throws -> Void) -> Task<Cancellation, Never>? {
            guard reconciliation == nil, case .unrecorded = cancellation else { return nil }
            inquiry?.cancel()
            return reconcile(using: {
                do {
                    try await record()
                    return .cancelled
                } catch {
                    return .unrecorded(Self.sentence(for: error))
                }
            })
        }

        /// The screen went away — the read ends with it (rule 6). Reconciliation
        /// lives in a slot `stop()` never touches: an accepted cancellation's
        /// re-read or history write runs to the end either way, because
        /// abandoning it strands a paid cancellation between the wire's truth
        /// and history's memory (review, PR #32).
        func stop() {
            inquiry?.cancel()
            inquiry = nil
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
            .environment(StoreController(database: nil))
    }
}

#Preview("Done — terminal") {
    NavigationStack {
        OrderDetailView(order: .previewDone)
            .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
            .environment(StoreController(database: nil))
    }
}
