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
            reload: { Task { await model.load(using: loadCancellation) } },
            confirm: { Task { await model.confirm(using: cancel) } }
        )
        .navigationTitle(Text("Order"))
        .task {
            guard order.isCancellable else { return }
            await model.load(using: loadCancellation)
        }
    }

    /// Both reads live behind the claim id — absent it, there is nothing to ask.
    private func loadCancellation() async throws -> ClaimCancellation {
        guard let id = order.claimID else { throw OffersUnavailable() }
        return try await session.claimCancellation(id: id)
    }

    /// Cancels, then rewrites the local order's status — the store upserts by id, so
    /// history keeps one row that now says cancelled.
    private func cancel(_ cancellation: ClaimCancellation) async throws {
        guard let id = order.claimID else { return }
        _ = try await session.cancelClaim(
            id: id, version: cancellation.version, terms: cancellation.terms
        )
        var updated = order
        updated.status = .cancelled
        try await store.record(updated)
    }
}

extension OrderDetailView {
    /// The cancellation ask's state machine — the screen's only moving part. History
    /// is the caller's: the model reports the answer; the root view records it.
    @Observable @MainActor
    final class Model {
        private(set) var cancellation: Cancellation = .loading

        enum Cancellation: Hashable {
            /// Asking the provider what cancelling costs.
            case loading
            /// Terms in hand — free, priced, or refused by the wire's own rules.
            case ready(ClaimCancellation)
            /// The ask failed; the reason renders as it arrived.
            case failed(String)
            /// Confirmed, in flight.
            case cancelling
            /// The provider said cancelled — terminal.
            case cancelled
        }

        func load(using fetch: () async throws -> ClaimCancellation) async {
            cancellation = .loading
            do {
                cancellation = .ready(try await fetch())
            } catch {
                guard !Task.isCancelled else { return }
                cancellation = .failed(Self.sentence(for: error))
            }
        }

        /// The confirm button's whole job — refuses to fire unless terms are in hand
        /// and the wire hasn't already closed the door.
        func confirm(using cancel: (ClaimCancellation) async throws -> Void) async {
            guard case .ready(let current) = cancellation,
                  current.terms != .unavailable
            else { return }
            cancellation = .cancelling
            do {
                try await cancel(current)
                cancellation = .cancelled
            } catch {
                guard !Task.isCancelled else { return }
                cancellation = .failed(Self.sentence(for: error))
            }
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
