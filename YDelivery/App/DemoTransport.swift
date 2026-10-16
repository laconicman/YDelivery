import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Answers the provider API from canned data held in memory — the App Review
/// demonstration account. Signing in with the token `demo`
/// (``ClientController/demoToken``) builds a session whose every call lands here:
/// no network, no courier, no charge — which is the point, because a real
/// claim dispatches a real courier the reviewer would be billed for (the
/// rejection under Guideline 2.1(a) noted the app was unusable without one).
///
/// Three claims are seeded so a first sync populates Deliveries the way a real
/// account's history does; a claim the reviewer places joins them — its route
/// points and items are echoed out of the create body, so the new order shows
/// the addresses they picked rather than another canned row. Accepting flips it
/// to a courier on the way, cancelling cancels it, and the journal grows the
/// same status trail the wire carries, so the list, the detail timeline,
/// cancellation and Diagnostics all exercise real code paths.
///
/// The shapes mirror `openapi.yaml` in `YandexDeliveryExpressAPI` and the live
/// captures that informed it (the package's `SearchClaimsResponse` fixture is
/// the pattern for the claim objects). Nothing here is reachable with a real
/// credential — that session keeps its `URLSessionTransport`.
actor DemoTransport: ClientTransport {
    /// Every claim the demo knows, by id. Values are wire-shaped objects —
    /// `[String: Any]` — mutated on accept/cancel so the next read sees them.
    private var claims: [String: [String: Any]] = [:]
    /// Insertion order, so `claims/search` answers stably.
    private var claimOrder: [String] = []
    /// The journal `getClaimsJournal` replays — grows as claims are created,
    /// accepted and cancelled, one row per `status_changed` the wire would send.
    private var journal: [[String: Any]] = []
    /// `operation_id` is the journal's position — strictly increasing.
    private var nextOperationID: Int64 = 1
    /// Mints `demo…` claim ids for created claims — 32 chars like the wire's.
    private var nextClaimSerial = 4

    init() {
        let now = Date.now
        for seed in [DemoClaims.enRoute(now: now), DemoClaims.delivered(now: now),
                     DemoClaims.unclaimed(now: now)] {
            let id = seed.claim["id"] as! String
            claims[id] = seed.claim
            claimOrder.append(id)
            for event in seed.events {
                var row = event
                row["operation_id"] = nextOperationID
                row["claim_id"] = id
                nextOperationID += 1
                journal.append(row)
            }
        }
    }

    // MARK: - ClientTransport

    /// The protocol's `send` is a nonisolated requirement, so it cannot touch
    /// the actor's state itself — it hops straight to ``route``, which can.
    nonisolated func send(
        _ request: HTTPRequest,
        body requestBody: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        try await route(request, body: requestBody, operationID: operationID)
    }

    private func route(
        _ request: HTTPRequest,
        body requestBody: HTTPBody?,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let claimID = Self.claimID(from: request)
        let requestObject = try await Self.jsonObject(from: requestBody)
        switch operationID {
        case "calculateOffers":
            return respond(.ok, DemoClaims.offers())
        case "createClaim":
            return respond(.ok, createClaim(from: requestObject))
        case "acceptClaim":
            return accept(claimID)
        case "getClaimInfo":
            return claimResponse(claimID)
        case "getClaimCancelInfo":
            return cancelTerms(claimID)
        case "cancelClaim":
            return cancel(claimID)
        case "searchClaims":
            return respond(.ok, search(state: requestObject?["state"] as? String))
        case "getClaimsJournal":
            return respond(.ok, journalPage(after: requestObject?["cursor"] as? String))
        default:
            return respond(.notFound, Self.refusal(
                code: "not_found", message: "The demo account does not serve \(operationID)"))
        }
    }

    // MARK: - Mutations

    /// A create whose answer is already priced — the real claim passes through
    /// `estimating` first; here `ready_for_approval` lets the ordering flow
    /// proceed to acceptance without a wait it cannot distinguish from lag.
    /// Route points and items are echoed so the order carries the reviewer's
    /// own addresses — `point_id` in the request becomes `id` in the claim.
    private func createClaim(from request: [String: Any]?) -> [String: Any] {
        let id = String(format: "demo%028d", nextClaimSerial)
        nextClaimSerial += 1
        let now = Date.now
        let points = (request?["route_points"] as? [[String: Any]] ?? [])
            .enumerated()
            .map { index, point -> [String: Any] in
                var routed = point
                routed["id"] = point["point_id"] ?? index + 1
                routed.removeValue(forKey: "point_id")
                routed["visit_status"] = "pending"
                routed["visited_at"] = [String: Any]()
                return routed
            }
        // The chosen offer's payload (`demo-<class>`) is the truer source for
        // the claim's price than `client_requirements` — they travel together,
        // but the payload is what the sender actually accepted.
        let payload = request?["offer_payload"] as? String ?? ""
        let taxiClass = payload.hasPrefix("demo-")
            ? String(payload.dropFirst("demo-".count))
            : ((request?["client_requirements"] as? [String: Any])?["taxi_class"]
                as? String ?? "express")
        var claim: [String: Any] = [
            "id": id,
            "corp_client_id": "demo",
            "status": "ready_for_approval",
            "version": 1,
            "revision": 3,
            "user_request_revision": "1",
            "created_ts": Self.timestamp(now),
            "updated_ts": Self.timestamp(now),
            "last_status_change_ts": Self.timestamp(now),
            "route_points": points,
            "items": request?["items"] ?? [],
            "current_point_id": points.first?["id"] ?? 1,
            "client_requirements": request?["client_requirements"]
                ?? ["taxi_class": taxiClass, "cargo_loaders": 0,
                    "cargo_options": [String](), "pro_courier": false],
            "due": request?["due"] ?? Self.timestamp(now.addingTimeInterval(1800)),
            "comment": request?["comment"] ?? "",
            "skip_door_to_door": request?["skip_door_to_door"] ?? false,
            "skip_client_notify": false,
            "optional_return": false,
            "same_day_data": [
                "delivery_interval": [
                    "from": Self.timestamp(now.addingTimeInterval(1800)),
                    "to": Self.timestamp(now.addingTimeInterval(7200)),
                ],
            ],
            "eta": 15,
            "pricing": DemoClaims.pricing(total: DemoClaims.price(forTaxiClass: taxiClass)),
            "available_cancel_state": "free",
            "emergency_contact": DemoClaims.emergencyContact,
            "error_messages": [String](),
        ]
        store(&claim)
        let revision = Int64(1)
        appendEvent(claimID: id, status: "new", at: now, revision: revision)
        appendEvent(claimID: id, status: "estimating",
                    at: now.addingTimeInterval(1), revision: revision + 1)
        appendEvent(claimID: id, status: "ready_for_approval",
                    at: now.addingTimeInterval(2), revision: revision + 2)
        return claim
    }

    /// The wire's accept answer says `accepted`; the claim itself moves on to a
    /// courier found, so the reviewer's order shows the live state (and a
    /// cancellable one) rather than sitting in «searching» forever. Two status
    /// flips, two journal rows — the same trail the wire would grow.
    private func accept(_ claimID: String?) -> (HTTPResponse, HTTPBody?) {
        guard let claimID, var claim = claims[claimID] else {
            return respond(.notFound, Self.notFound)
        }
        let now = Date.now
        mutate(&claim, status: "accepted", at: now)
        appendEvent(claimID: claimID, status: "accepted",
                    at: now, revision: revision(of: claim))
        claim["performer_info"] = DemoClaims.performer
        mutate(&claim, status: "performer_found", at: now.addingTimeInterval(2))
        appendEvent(claimID: claimID, status: "performer_found",
                    at: now.addingTimeInterval(2), revision: revision(of: claim))
        return respond(.ok, [
            "id": claimID,
            "skip_client_notify": false,
            "status": "accepted",
            "user_request_revision": "1",
            "version": claim["version"] ?? 1,
        ])
    }

    /// `cancelled`, matching the free/paid terms `cancel-info` advertised — the
    /// paid seed carries `resolution: failed` on its journal row, the wire's own
    /// quirk for a user cancellation (JournalEvent's doc note).
    private func cancel(_ claimID: String?) -> (HTTPResponse, HTTPBody?) {
        guard let claimID, var claim = claims[claimID] else {
            return respond(.notFound, Self.notFound)
        }
        let status = (claim["available_cancel_state"] as? String) == "paid"
            ? "cancelled_with_payment" : "cancelled"
        let now = Date.now
        mutate(&claim, status: status, at: now)
        appendEvent(claimID: claimID, status: status, at: now,
                    resolution: "failed", revision: revision(of: claim))
        return respond(.ok, [
            "id": claimID,
            "skip_client_notify": false,
            "status": status,
            "version": claim["version"] ?? 1,
        ])
    }

    // MARK: - Reads

    private func claimResponse(_ claimID: String?) -> (HTTPResponse, HTTPBody?) {
        guard let claimID, let claim = claims[claimID] else {
            return respond(.notFound, Self.notFound)
        }
        return respond(.ok, claim)
    }

    /// Terms mirror `available_cancel_state`: the en-route seed is `paid` so the
    /// fee-confirming cancellation UI is demoable; finished claims refuse.
    private func cancelTerms(_ claimID: String?) -> (HTTPResponse, HTTPBody?) {
        guard let claimID, let claim = claims[claimID] else {
            return respond(.notFound, Self.notFound)
        }
        return switch claim["available_cancel_state"] as? String {
        case "paid":
            respond(.ok, ["cancel_state": "paid", "currency": "RUB",
                          "price": "400", "price_with_vat": "400"])
        case "free":
            respond(.ok, ["cancel_state": "free"])
        default:
            respond(.ok, ["cancel_state": "unavailable"])
        }
    }

    /// `state` buckets the way `SearchClaimState` is observed to: `finished`
    /// holds delivered/cancelled/unmatched, `active` everything still moving.
    /// No cursor — one page holds the whole demo history.
    private func search(state: String?) -> [String: Any] {
        let matching = claimOrder.compactMap { claims[$0] }.filter { claim in
            let status = claim["status"] as? String ?? ""
            return switch state {
            case "finished": DemoClaims.finishedStatuses.contains(status)
            case "delayed": DemoClaims.delayedStatuses.contains(status)
            default: !DemoClaims.finishedStatuses.contains(status)
                    && !DemoClaims.delayedStatuses.contains(status)
            }
        }
        return ["claims": matching]
    }

    // MARK: - Journal

    /// Journal semantics, not a firehose: the cursor is the last `operation_id`
    /// served, and the answer carries only rows after it — the caller pages
    /// until `events` empties, which a whole-journal-every-time answer would
    /// make the 20-page cap eat every pass.
    private func journalPage(after cursor: String?) -> [String: Any] {
        let position = cursor.flatMap(Int64.init) ?? 0
        let fresh = journal.filter {
            ($0["operation_id"] as? Int64 ?? 0) > position
        }
        return ["cursor": String(nextOperationID - 1), "events": fresh]
    }

    /// One `status_changed` row — the app folds these into the detail timeline;
    /// `current_point_id` names the route point the status happened at.
    private func appendEvent(
        claimID: String, status: String, at: Date,
        resolution: String? = nil, revision: Int64
    ) {
        var event: [String: Any] = [
            "operation_id": nextOperationID,
            "claim_id": claimID,
            "change_type": "status_changed",
            "new_status": status,
            "updated_ts": Self.timestamp(at),
            "revision": revision,
            "current_point_id": claims[claimID]?["current_point_id"] ?? 1,
        ]
        event["resolution"] = resolution
        nextOperationID += 1
        journal.append(event)
    }

    /// The claim's own revision — `mutate` bumps it, journal rows quote it.
    private func revision(of claim: [String: Any]) -> Int64 {
        (claim["revision"] as? Int64) ?? Int64(claim["revision"] as? Int ?? 0)
    }

    // MARK: - State plumbing

    /// Register a created claim — the same bookkeeping a seed got at init,
    /// sans the trail, which the create appends itself.
    private func store(_ claim: inout [String: Any]) {
        let id = claim["id"] as! String
        claims[id] = claim
        claimOrder.append(id)
    }

    /// Apply a status flip to the stored object — status, change stamps,
    /// revision bump — so the next `info`/`search` read sees it.
    private func mutate(_ claim: inout [String: Any], status: String, at: Date) {
        let id = claim["id"] as! String
        claim["status"] = status
        claim["updated_ts"] = Self.timestamp(at)
        claim["last_status_change_ts"] = Self.timestamp(at)
        claim["revision"] = revision(of: claim) + 1
        claims[id] = claim
    }

    // MARK: - Response plumbing

    private func respond(
        _ status: HTTPResponse.Status, _ object: [String: Any]
    ) -> (HTTPResponse, HTTPBody?) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        var response = HTTPResponse(status: status)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(data))
    }

    /// The claim id rides in the query for every single-claim operation —
    /// `claims/info?claim_id=…`, `cancel-info`, `accept`, `cancel`.
    private static func claimID(from request: HTTPRequest) -> String? {
        URLComponents(string: request.path ?? "")
            .flatMap(\.queryItems)?
            .first(where: { $0.name == "claim_id" })?
            .value
    }

    private static func jsonObject(from body: HTTPBody?) async throws -> [String: Any]? {
        guard let body else { return nil }
        let text = try await String(collecting: body, upTo: .max)
        return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    private static func refusal(code: String, message: String) -> [String: Any] {
        ["code": code, "message": message]
    }

    private static var notFound: [String: Any] {
        refusal(code: "not_found", message: "claim not found")
    }

    private static func timestamp(_ date: Date) -> String {
        DemoClaims.timestamp(date)
    }
}
