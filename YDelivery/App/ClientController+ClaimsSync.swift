import Foundation
import YandexDeliveryExpressAPI

// The discovery pair of package 0.3.0 — the wire half of the claims list's hybrid
// sync (Design → "Claims sync"): `claims/search` answers *what exists*, `claims/journal`
// answers *what changed*. Generated types end here, as everywhere in this layer —
// `ClaimsSync` maps them into `Order`s.
extension ClientController {
    /// One journal page from the persisted position. The cursor is opaque — stored
    /// verbatim between launches, handed back untouched; `invalid_cursor` is the one
    /// refusal that means "replay from the beginning", so it travels as its own error
    /// rather than a refusal the list would render.
    func journalPage(cursor: String?) async throws -> Components.Schemas.ClaimsJournalResponse {
        guard let client else { throw OffersUnavailable() }
        let body: Operations.GetClaimsJournal.Input.Body? = cursor.map { .json(.init(cursor: $0)) }
        return try Self.journalPage(from: await client.getClaimsJournal(
            query: .init(limit: Self.journalPageLimit),
            body: body
        ))
    }

    /// One search page — a filter variant on the first call, the provider's
    /// continuation variant after. Those are two different request bodies on the
    /// wire (the API's own `oneOf`), which is why the cursor path takes nothing else:
    /// a filter stapled to a continuation is refused.
    func searchPage(
        state: Components.Schemas.SearchClaimState,
        cursor: String?
    ) async throws -> Components.Schemas.SearchClaimsResponse {
        guard let client else { throw OffersUnavailable() }
        let request: Components.Schemas.SearchClaimsRequest = if let cursor {
            .SearchClaimsRequestCursor(.init(cursor: cursor))
        } else {
            .SearchClaimsRequestCorp(.init(limit: Int64(Self.searchPageLimit), state: state))
        }
        return try Self.searchPage(from: await client.searchClaims(.init(
            headers: .init(acceptLanguage: .ru),
            body: .json(request)
        )))
    }

    /// The whole claim card — how a journal event for a claim history never recorded
    /// becomes a row: the feed carries only ids and deltas, never routes or prices.
    func claimCard(id: String) async throws -> Components.Schemas.ClaimResponse {
        guard let client else { throw OffersUnavailable() }
        return try Self.claimInfo(from: await client.getClaimInfo(.init(
            query: .init(claimId: id),
            headers: .init(acceptLanguage: .ru)
        )))
    }

    /// Page sizes: journal events are thin rows; search returns whole claim cards.
    /// A sync pass that outruns them stops on the controller's own counter, never on
    /// the provider's patience.
    static let journalPageLimit = 500
    static let searchPageLimit = 200

    /// The journal answer read the honest way — documented refusals keep the
    /// provider's `{code, message}` (the `.ok` accessor would bury them), and the
    /// `invalid_cursor` code is unwrapped into the engine's replay signal.
    nonisolated static func journalPage(
        from response: Operations.GetClaimsJournal.Output
    ) throws -> Components.Schemas.ClaimsJournalResponse {
        switch response {
        case .ok(let ok):
            return try ok.body.json
        case .badRequest(let error):
            let body = try? error.body.json
            if body?.code == "invalid_cursor" { throw JournalCursorInvalid() }
            throw ProviderRefusal(message: body?.message)
        case .unauthorized(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .tooManyRequests(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .internalServerError(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .undocumented(let statusCode, _):
            throw ProviderRefusal(message: nil, status: statusCode)
        }
    }

    /// The search answer read the same honest way.
    nonisolated static func searchPage(
        from response: Operations.SearchClaims.Output
    ) throws -> Components.Schemas.SearchClaimsResponse {
        switch response {
        case .ok(let ok):
            return try ok.body.json
        case .badRequest(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .unauthorized(let error):
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
