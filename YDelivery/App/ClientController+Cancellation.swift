import Foundation
import YandexDeliveryExpressAPI

// Cancelling a placed claim — asking what it would cost, then doing it. Same boundary
// as `ClientController+Claims`: generated types die here, and documented refusals keep
// the provider's own `{code, message}` rather than an accessor error (PR #31's lesson,
// applied at birth rather than retrofitted).
extension ClientController {
    /// Where the claim stands plus what cancelling costs — two reads in parallel,
    /// because the version the cancel call must name moves with the courier.
    func claimCancellation(id: String) async throws -> ClaimCancellation {
        guard let client else { throw OffersUnavailable() }
        async let claimFetch = claimState(id: id)
        async let infoFetch = client.getClaimCancelInfo(.init(
            query: .init(claimId: id),
            headers: .init(acceptLanguage: .ru)
        ))
        let claim = try await claimFetch
        let terms = try await Self.cancelTerms(from: infoFetch)
        return ClaimCancellation(status: claim.status, version: claim.version, terms: terms)
    }

    /// Cancels, naming the version and the kind of cancellation the terms advertised.
    /// `unavailable` terms are refused here too — the screen's button is the first
    /// guard, this is the second, because terms can go stale between them.
    func cancelClaim(
        id: String,
        version: Int,
        terms: ClaimCancellation.Terms
    ) async throws -> PlacedClaim {
        guard let client else { throw OffersUnavailable() }
        let state: Components.Schemas.CancelState = switch terms {
        case .free: .free
        case .paid: .paid
        case .unavailable: throw ClaimUncancellable()
        }
        let response = try await client.cancelClaim(.init(
            query: .init(claimId: id),
            headers: .init(acceptLanguage: .ru),
            body: .json(.init(version: Int64(version), cancelState: state))
        ))
        // A 200 is the request's word, not the claim's — the doc's own example returns
        // `"status": "new"` for a cancelled claim. The same lesson the ordering flow
        // already learned: the answer is not assumed, the claim's fresh state is read
        // back (Russian doc, claims/cancel, 2026-09-22).
        try Self.cancelAccepted(from: response)
        let standing = try await claimState(id: id)
        guard standing.status.isCancelled else {
            throw CancellationUnconfirmed(status: String(describing: standing.status))
        }
        return standing
    }

    /// The cancel answer's refusal half: documented non-200s keep the provider's
    /// `{code, message}` — a 409 here is the stale-version refusal (`inappropriate_status`,
    /// Russian doc) — while a 200's body is deliberately not decoded into truth.
    nonisolated static func cancelAccepted(
        from response: Operations.CancelClaim.Output
    ) throws {
        switch response {
        case .ok:
            return
        case .badRequest(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .unauthorized(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .conflict(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .tooManyRequests(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .internalServerError(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .undocumented(let statusCode, _):
            throw ProviderRefusal(message: nil, status: statusCode)
        }
    }

    /// The terms half of ``claimCancellation(id:)`` — `claimState` reads status and
    /// version; this decodes the provider's `cancel_state` into the app's vocabulary.
    /// `paid` keeps the with-VAT figure, the number this app quotes everywhere money
    /// appears (``Offer``'s mapping made that choice first).
    nonisolated static func cancelTerms(
        from response: Operations.GetClaimCancelInfo.Output
    ) throws -> ClaimCancellation.Terms {
        switch response {
        case .ok(let ok):
            let info = try ok.body.json
            return switch info.cancelState {
            case .free: .free
            case .paid:
                    .paid(
                        price: (info.priceWithVat ?? info.price).flatMap {
                            Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
                        },
                        currency: info.currency?.rawValue
                    )
            case .unavailable: .unavailable
            }
        case .badRequest(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .unauthorized(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .notFound(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .conflict(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .tooManyRequests(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .internalServerError(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .undocumented(let statusCode, _):
            throw ProviderRefusal(message: nil, status: statusCode)
        }
    }
}
