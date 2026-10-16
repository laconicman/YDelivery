import Foundation
import Testing
import YandexDeliveryExpressAPI
import YDeliveryKit
@testable import YDelivery

/// The App Review demonstration account's wire — canned JSON flowing through the
/// real generated `Client`, so the suite answers "does the demo's data satisfy
/// the schema the decoder enforces" rather than "did we spell a dictionary
/// right". A field the spec rejects fails here before a reviewer finds it.
@Suite("Demo transport")
@MainActor
struct DemoTransportTests {
    private func client() throws -> Client {
        try Client(
            credentials: Credentials(authToken: ClientController.demoToken),
            middlewares: [],
            transport: DemoTransport())
    }

    private func search(
        _ client: Client, state: Components.Schemas.SearchClaimState
    ) async throws -> [Components.Schemas.ClaimResponse] {
        let output = try await client.searchClaims(.init(
            headers: .init(acceptLanguage: .ru),
            body: .json(.SearchClaimsRequestCorp(.init(limit: 200, state: state)))))
        guard case .ok(let ok) = output else {
            Issue.record("searchClaims answered \(output)")
            return []
        }
        return try ok.body.json.claims
    }

    private func card(
        _ client: Client, id: String
    ) async throws -> Components.Schemas.ClaimResponse {
        let output = try await client.getClaimInfo(.init(
            query: .init(claimId: id), headers: .init(acceptLanguage: .ru)))
        return try ClientController.claimInfo(from: output)
    }

    @Test("Seeded history decodes into live, done and attention rows")
    func seededHistory() async throws {
        let client = try client()

        let active = try await search(client, state: .active)
        #expect(active.count == 1)
        let live = Order(claim: active[0], adoptingID: UUID())
        #expect(live.status == .active, "performer_found is a courier on the way")
        #expect(live.courierName == "Алексей Смирнов")
        #expect(live.price == "890.00")
        #expect(live.providerStatus == "performer_found")

        let finished = try await search(client, state: .finished)
        #expect(finished.count == 2)
        let states = finished.map { Order(claim: $0, adoptingID: UUID()).status }
        #expect(states.contains(.done), "delivered claim fills the done row")
        #expect(states.contains(.attention),
                "performer_not_found fills needs-a-decision")
    }

    @Test("The journal carries each seeded claim's status trail")
    func journal() async throws {
        let client = try client()
        let output = try await client.getClaimsJournal(
            query: .init(limit: 500), body: nil)
        guard case .ok(let ok) = output else {
            Issue.record("getClaimsJournal answered \(output)")
            return
        }
        let events = try ok.body.json.events
        #expect(events.count == 19, "6 + 10 + 3 seeded status changes")
        #expect(Set(events.map(\.changeType)) == [.statusChanged])
        // The merge the sync runs — a seeded claim's last word wins.
        let live = events.filter { $0.newStatus == .performerFound }
        #expect(live.count == 2,
                "the en-route claim and the delivered one's full lifecycle both carry it")

        // The cursor the page just issued buys an empty next page — the sync's
        // loop ends on `events.isEmpty`, and a transport that re-serves the
        // whole feed would spend every pass inside the 20-page cap instead.
        let cursor = try #require(try ok.body.json.cursor)
        let drained = try await client.getClaimsJournal(
            query: .init(limit: 500), body: .json(.init(cursor: cursor)))
        guard case .ok(let drainedOK) = drained else {
            Issue.record("getClaimsJournal answered \(drained)")
            return
        }
        #expect(try drainedOK.body.json.events.isEmpty)
    }

    /// A create echoes the requester's own route and items — the reviewer's
    /// order must show the addresses *they* picked, not canned ones.
    @Test("A placed claim echoes the draft, prices its tariff, then moves")
    func placedClaimLifecycle() async throws {
        let client = try client()
        var item = ParcelItem()
        item.name = "Документы"
        item.quantity = 1
        let order = OrderRequest(
            points: [
                .init(
                    pointID: UUID(),
                    latitude: 55.7567, longitude: 37.6277,
                    address: "Москва, Никольская улица, 10",
                    parts: nil,
                    contact: Contact(givenName: "Ольга", phone: "+7 916 123-45-67"),
                    role: .pickup
                ),
                .init(
                    pointID: UUID(),
                    latitude: 55.7425, longitude: 37.6290,
                    address: "Москва, Пятницкая улица, 25",
                    parts: nil,
                    contact: Contact(givenName: "Сергей", phone: "+7 926 987-65-43"),
                    role: .dropoff
                ),
            ],
            items: [item],
            options: DeliveryOptions(),
            offerPayload: "demo-express",
            tariff: .express
        )
        let created = try ClientController.createdClaim(from: try await client
            .createClaim(.init(
                query: .init(requestId: "demo-test"),
                headers: .init(acceptLanguage: .ru),
                body: .json(try ClientController.createRequest(for: order)))))
        #expect(created.status == .readyToAccept)

        // The request_id replays rather than duplicating — the ordering flow's
        // idempotent retry must not mint a second claim (nor, on the wire, a
        // second courier).
        let replayed = try ClientController.createdClaim(from: try await client
            .createClaim(.init(
                query: .init(requestId: "demo-test"),
                headers: .init(acceptLanguage: .ru),
                body: .json(try ClientController.createRequest(for: order)))))
        #expect(replayed.id == created.id)

        // The card echoes the draft's own route — the reviewer sees their stops.
        let claim = try await card(client, id: created.id)
        let mapped = Order(claim: claim, adoptingID: UUID())
        #expect(mapped.route.first?.address == "Москва, Никольская улица, 10")
        #expect(mapped.route.last?.address == "Москва, Пятницкая улица, 25")
        #expect(mapped.price == "1240.00", "the express offer's price")
        #expect(mapped.status == .attention, "ready_for_approval asks a decision")

        // Accept — a courier appears and the row goes live.
        let acceptOutput = try await client.acceptClaim(.init(
            query: .init(claimId: created.id),
            headers: .init(acceptLanguage: .ru),
            body: .json(.init(version: Int64(created.version)))))
        guard case .ok = acceptOutput else {
            Issue.record("acceptClaim answered \(acceptOutput)")
            return
        }
        let accepted = try await card(client, id: created.id)
        let live = Order(claim: accepted, adoptingID: UUID())
        #expect(accepted.status == .performerFound)
        #expect(live.status == .active)
        #expect(live.courierName == "Алексей Смирнов")
        #expect(try await search(client, state: .active).count == 2)

        // Terms are free for a demo-created claim; the cancel lands.
        let terms = try await client.getClaimCancelInfo(.init(
            query: .init(claimId: created.id),
            headers: .init(acceptLanguage: .ru)))
        guard case .ok(let termsOK) = terms,
              case .free = try termsOK.body.json.cancelState else {
            Issue.record("cancel-info answered \(terms)")
            return
        }
        let cancel = try await client.cancelClaim(.init(
            query: .init(claimId: created.id),
            headers: .init(acceptLanguage: .ru),
            body: .json(.init(version: Int64(created.version), cancelState: .free))))
        guard case .ok = cancel else {
            Issue.record("cancelClaim answered \(cancel)")
            return
        }
        let cancelled = try await card(client, id: created.id)
        #expect(cancelled.status == .cancelled)
        #expect(try await search(client, state: .finished).count == 3)
        #expect(try await search(client, state: .active).count == 1)
    }

    @Test("The en-route seed asks for paid cancellation; finished refuse")
    func cancelTerms() async throws {
        let client = try client()
        let paid = try await client.getClaimCancelInfo(.init(
            query: .init(claimId: "demo0000000000000000000000000001"),
            headers: .init(acceptLanguage: .ru)))
        guard case .ok(let paidOK) = paid else {
            Issue.record("cancel-info answered \(paid)")
            return
        }
        let info = try paidOK.body.json
        guard case .paid = info.cancelState else {
            Issue.record("expected paid terms, got \(info.cancelState)")
            return
        }
        #expect(info.priceWithVat == "400")

        let refused = try await client.getClaimCancelInfo(.init(
            query: .init(claimId: "demo0000000000000000000000000002"),
            headers: .init(acceptLanguage: .ru)))
        guard case .ok(let refusedOK) = refused else {
            Issue.record("cancel-info answered \(refused)")
            return
        }
        #expect(try refusedOK.body.json.cancelState == .unavailable)
    }

    @Test("Offers decode with three tariffs priced against now")
    func offers() async throws {
        let client = try client()
        // The draft's own request builder — the demo answers what the app asks.
        let request = OfferRequest(
            waypoints: [
                .init(pointID: UUID(), latitude: 55.7567, longitude: 37.6277,
                      address: "Москва, Никольская улица, 10", role: .pickup),
                .init(pointID: UUID(), latitude: 55.7425, longitude: 37.6290,
                      address: "Москва, Пятницкая улица, 25", role: .dropoff),
            ],
            items: [], options: DeliveryOptions())
        let output = try await client.calculateOffers(.init(
            headers: .init(acceptLanguage: .ru),
            body: .json(ClientController.offersRequest(for: request))))
        guard case .ok(let ok) = output else {
            Issue.record("calculateOffers answered \(output)")
            return
        }
        let classes = try ok.body.json.offers.map(\.taxiClass)
        #expect(classes == [.courier, .express, .superexpressD2d])
    }

    @Test("The demo token builds a flagged demo session; a real token stays network-backed")
    func sentinelSignIn() async {
        let store = TokenStore(service: "tests.YDelivery.demo.\(UUID().uuidString)")
        defer { try? store.delete() }
        let controller = ClientController(tokenStore: store)
        #expect(!controller.isDemoSession)

        await controller.signIn(token: " demo ")
        #expect(controller.isSignedIn)
        #expect(controller.isDemoSession)
        #expect(controller.signInError == nil)

        controller.signOut()
        #expect(!controller.isSignedIn)
        #expect(!controller.isDemoSession)

        await controller.signIn(token: "y0_a-real-looking-token")
        #expect(controller.isSignedIn)
        #expect(!controller.isDemoSession)
    }
}
