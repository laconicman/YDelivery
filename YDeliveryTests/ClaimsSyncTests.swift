import Foundation
import OpenAPIRuntime
import Testing
import YandexDeliveryExpressAPI
import YDeliveryKit
@testable import YDelivery

/// Phase 3's claims sync — the wire vocabulary collapsing into the sender's, the
/// journal's events folded into history, and search's membership merged without
/// losing a row's local identity.
@Suite("Claims sync")
@MainActor
struct ClaimsSyncTests {

    // MARK: Fixtures

    private func claim(
        id: String,
        status: Components.Schemas.ClaimStatus = .delivered,
        createdTs: Date = Date(timeIntervalSince1970: 1_790_000_000)
    ) -> Components.Schemas.ClaimResponse {
        .init(
            createdTs: createdTs,
            id: id,
            items: [],
            revision: 1,
            routePoints: [
                .init(
                    id: 2,
                    address: .init(
                        fullname: "Москва, Каширское шоссе, 52",
                        coordinates: [37.648210, 55.652212],
                        doorCode: "12",
                        porch: "3",
                        sflat: "45",
                        sfloor: "4"
                    ),
                    contact: .init(name: "Анна", phone: "+7 999 444-55-66", phoneAdditionalCode: "77"),
                    _type: ._return,
                    visitOrder: 2,
                    visitStatus: .pending,
                    visitedAt: .init()
                ),
                .init(
                    id: 1,
                    address: .init(fullname: "Москва, ул Москворечье, 6", coordinates: [37.668176, 55.646068]),
                    contact: .init(name: "Иван", phone: "+7 999 111-22-33"),
                    _type: .source,
                    visitOrder: 1,
                    visitStatus: .visited,
                    visitedAt: .init()
                ),
            ],
            status: status,
            updatedTs: createdTs,
            userRequestRevision: "r1",
            version: 1,
            clientRequirements: .init(taxiClass: .express),
            pricing: .init(currency: .rub, finalPrice: "1190")
        )
    }

    private func event(
        claimId: String = "claim-1",
        changeType: Components.Schemas.JournalChangeType = .statusChanged,
        newStatus: Components.Schemas.ClaimStatus? = .delivered,
        newPrice: String? = nil,
        newCurrency: String? = nil
    ) -> Components.Schemas.JournalEvent {
        .init(
            changeType: changeType,
            claimId: claimId,
            operationId: 1,
            revision: 2,
            updatedTs: Date(timeIntervalSince1970: 1_790_000_100),
            newCurrency: newCurrency,
            newPrice: newPrice,
            newStatus: newStatus
        )
    }

    private func order(claimID: String?, status: OrderStatus = .searching) -> Order {
        Order(
            id: UUID(),
            created: Date(timeIntervalSince1970: 1_790_000_000),
            status: status,
            route: [RoutePoint(latitude: 55.6, longitude: 37.6, address: "Откуда")],
            claimID: claimID
        )
    }

    // MARK: Status vocabulary — YD-7's discharge

    @Test("Every wire status lands in the sender's six — the whole zoo, no raw words")
    func statusVocabulary() {
        let expected: [Components.Schemas.ClaimStatus: OrderStatus] = [
            .new: .searching, .estimating: .searching,
            .accepted: .searching, .performerLookup: .searching, .performerDraft: .searching,
            .performerFound: .active, .pickupArrived: .active,
            .readyForPickupConfirmation: .active, .pickuped: .active,
            .deliveryArrived: .active, .readyForDeliveryConfirmation: .active,
            .returning: .active, .returnArrived: .active,
            .readyForReturnConfirmation: .active,
            .delivered: .done, .deliveredFinish: .done,
            .cancelled: .cancelled, .cancelledWithPayment: .cancelled,
            .cancelledByTaxi: .cancelled, .cancelledWithItemsOnHands: .cancelled,
            .readyForApproval: .attention, .estimatingFailed: .attention,
            .performerNotFound: .attention, .payWaiting: .attention,
            .failed: .attention, .returned: .attention, .returnedFinish: .attention,
        ]
        for status in Components.Schemas.ClaimStatus.allCases {
            #expect(
                OrderStatus(claimStatus: status) == expected[status],
                "\(status.rawValue) must land in a named state, not a raw word"
            )
        }
    }

    // MARK: Claim → Order

    @Test("A claim becomes a row: wire spellings back into the store's vocabulary")
    func claimBecomesOrder() {
        let id = UUID()
        let order = Order(claim: claim(id: "claim-9", status: .performerFound), adoptingID: id)

        #expect(order.id == id, "the local identity is adopted, never minted anew")
        #expect(order.claimID == "claim-9")
        #expect(order.status == .active)
        #expect(order.price == "1190")
        #expect(order.currency == "RUB")
        #expect(order.tariff == "express")

        // Route: visit_order wins over the wire's array order, and the wire's
        // `return` stays — this app *sends* its drop-off as `return`, so the last
        // stop is the sender's destination, not courier bookkeeping.
        let route = order.route
        #expect(route.count == 2)
        #expect(route[0].address == "Москва, ул Москворечье, 6")
        #expect(route[1].address == "Москва, Каширское шоссе, 52")

        // Coordinates read [lon, lat] — the same trap the create request answers.
        #expect(route[0].latitude == 55.646068)
        #expect(route[0].longitude == 37.668176)

        // Door details land in AddressParts' own names; the extension keeps its own
        // field — never folded into the phone.
        #expect(route[1].addressParts?.entrance == "3")
        #expect(route[1].addressParts?.floor == "4")
        #expect(route[1].addressParts?.apartment == "45")
        #expect(route[1].addressParts?.intercom == "12")
        #expect(route[1].contactName == "Анна")
        #expect(route[1].contactPhone == "+7 999 444-55-66")
        #expect(route[1].contactPhoneExtension == "77")
    }

    // MARK: Journal events

    @Test("A status event moves the known claim's row")
    func statusEventApplies() {
        let orders = [order(claimID: "claim-1", status: .active)]
        let updated = ClaimsSync.applying(event(newStatus: .delivered), to: orders)
        #expect(updated[0].status == .done)
    }

    @Test("A price event updates money, leaving status alone")
    func priceEventApplies() {
        let orders = [order(claimID: "claim-1", status: .active)]
        let updated = ClaimsSync.applying(
            event(changeType: .priceChanged, newStatus: nil, newPrice: "1300", newCurrency: "RUB"),
            to: orders
        )
        #expect(updated[0].price == "1300")
        #expect(updated[0].currency == "RUB")
        #expect(updated[0].status == .active)
    }

    @Test("An event for an unknown claim changes nothing — discovery is the caller's job")
    func unknownClaimEventIsNoOp() {
        let orders = [order(claimID: "claim-1")]
        let updated = ClaimsSync.applying(event(claimId: "claim-9"), to: orders)
        #expect(updated == orders)
    }

    @Test("A status event without a status changes nothing")
    func emptyStatusEventIsNoOp() {
        let orders = [order(claimID: "claim-1", status: .active)]
        let updated = ClaimsSync.applying(event(newStatus: nil), to: orders)
        #expect(updated == orders)
    }

    @Test("Only claim ids history lacks are reported missing — once each, in feed order")
    func missingClaimIDsReported() {
        let orders = [order(claimID: "claim-1")]
        let events = [
            event(claimId: "claim-1"),
            event(claimId: "claim-9"),
            event(claimId: "claim-9"),
            event(claimId: "claim-7"),
        ]
        #expect(ClaimsSync.missingClaimIDs(in: events, among: orders) == ["claim-9", "claim-7"])
    }

    // MARK: Journal replay — every event sets an absolute state

    @Test("Replaying an event is a no-op — the cursor's crash window is safe")
    func eventReplayIsIdempotent() {
        let orders = [order(claimID: "claim-1", status: .active)]
        let once = ClaimsSync.applying(event(newStatus: .delivered), to: orders)
        let twice = ClaimsSync.applying(event(newStatus: .delivered), to: once)
        #expect(twice == once)
        #expect(twice[0].status == .done)
    }

    @Test("An out-of-order event wins by arrival — absolute state, pinned")
    func eventOrderIsLastWriterWins() {
        let orders = [order(claimID: "claim-1", status: .done)]
        let stale = ClaimsSync.applying(event(newStatus: .pickuped), to: orders)
        #expect(stale[0].status == .active,
                "the last arrival wins — no version guard; ordered dedup is the event feed's job in the new schema")
    }

    // MARK: Search merge

    @Test("A searched claim updates in place — same local id, fresh wire truth")
    func mergeAdoptsStoredIdentity() {
        let stored = order(claimID: "claim-1", status: .searching)
        let merged = ClaimsSync.merging([claim(id: "claim-1", status: .delivered)], into: [stored])

        #expect(merged.count == 1, "one claim, one row — never a duplicate")
        #expect(merged[0].id == stored.id, "the row's identity survives the update")
        #expect(merged[0].status == .done)
        #expect(merged[0].price == "1190")
    }

    @Test("An unknown searched claim becomes a new row; orders stay newest-first")
    func mergeDiscoversAndOrders() {
        let stored = order(claimID: "claim-1", status: .searching)
        let older = claim(
            id: "claim-0",
            createdTs: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let merged = ClaimsSync.merging([older], into: [stored])

        #expect(merged.count == 2)
        #expect(merged[0].claimID == "claim-1", "the newer order leads")
        #expect(merged[1].claimID == "claim-0")
        #expect(merged[1].id != stored.id)
    }

    @Test("A claim matching no claimID leaves draft rows alone")
    func mergeLeavesLocalOnlyOrders() {
        let draft = order(claimID: nil, status: .draft)
        let merged = ClaimsSync.merging([claim(id: "claim-9")], into: [draft])
        #expect(merged.contains { $0.id == draft.id && $0.status == .draft })
    }

    // MARK: Merge identity — the concurrent-discovery lesson (review, PR #36)

    @Test("Re-merging a discovered claim keeps its row and id — rediscovery is not re-creation")
    func mergeIsIdempotentOnRediscovery() {
        let discovered = ClaimsSync.merging([claim(id: "claim-9", status: .new)], into: [])
        let rediscovered = ClaimsSync.merging([claim(id: "claim-9", status: .delivered)], into: discovered)

        #expect(rediscovered.count == 1, "the provider's claimID joins — never a second row")
        #expect(rediscovered[0].id == discovered[0].id,
                "the local id is adopted, never re-minted — the same rule the shared schema derives deterministically")
        #expect(rediscovered[0].status == .done)
    }

    @Test("The same claim twice in one feed page is still one row")
    func mergeDeduplicatesWithinBatch() {
        let merged = ClaimsSync.merging(
            [claim(id: "claim-9", status: .new), claim(id: "claim-9", status: .performerFound)],
            into: []
        )
        #expect(merged.count == 1)
        #expect(merged[0].status == .active, "the later card wins")
    }

    @Test("A thin card still becomes a row — no route, no price, no crash")
    func thinClaimBecomesOrder() {
        let thin = Components.Schemas.ClaimResponse(
            createdTs: Date(timeIntervalSince1970: 1_790_000_000),
            id: "claim-thin",
            items: [],
            revision: 1,
            routePoints: [],
            status: .new,
            updatedTs: Date(timeIntervalSince1970: 1_790_000_000),
            userRequestRevision: "r1",
            version: 1
        )
        let order = Order(claim: thin, adoptingID: UUID())
        #expect(order.route.isEmpty, "a card without stops is a row without a route, not a failure")
        #expect(order.price == nil)
        #expect(order.status == .searching)
    }

    // MARK: Wire refusals — the response mappers behind the engine

    @Test("invalid_cursor is the replay signal, not a refusal the list renders")
    func invalidCursorUnwraps() {
        let refusal = Operations.GetClaimsJournal.Output.badRequest(
            .init(body: .json(.init(code: "invalid_cursor", message: "cursor expired")))
        )
        #expect(throws: JournalCursorInvalid.self) {
            _ = try ClientController.journalPage(from: refusal)
        }
    }

    @Test("Other journal refusals keep the provider's words")
    func journalRefusalKeepsWords() {
        let refusal = Operations.GetClaimsJournal.Output.badRequest(
            .init(body: .json(.init(code: "parse_error", message: "Проверьте корректность")))
        )
        do {
            _ = try ClientController.journalPage(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "Проверьте корректность")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("An undocumented journal status keeps its code")
    func journalUndocumentedKeepsCode() {
        let output = Operations.GetClaimsJournal.Output.undocumented(statusCode: 502, .init())
        do {
            _ = try ClientController.journalPage(from: output)
            Issue.record("an undocumented status must throw")
        } catch let error as ProviderRefusal {
            #expect(error.status == 502)
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("Search refusals keep the provider's words")
    func searchRefusalKeepsWords() {
        let refusal = Operations.SearchClaims.Output.badRequest(
            .init(body: .json(.init(code: "parse_error", message: "bad json")))
        )
        do {
            _ = try ClientController.searchPage(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "bad json")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("An undocumented search status keeps its code")
    func searchUndocumentedKeepsCode() {
        let output = Operations.SearchClaims.Output.undocumented(statusCode: 502, .init())
        do {
            _ = try ClientController.searchPage(from: output)
            Issue.record("an undocumented status must throw")
        } catch let error as ProviderRefusal {
            #expect(error.status == 502)
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    // MARK: Sync state

    @Test("The cursor and the backfill flag round-trip together")
    func syncStateRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = AppDatabase(directory: directory)

        #expect(database.readSyncState() == .init(cursor: nil, historyBackfilled: false),
                "absent reads as first sync, never a crash")

        try database.writeSyncState(.init(cursor: "eyJ-opaque", historyBackfilled: true,
                                          pendingClaimIDs: ["claim-missed"]))
        #expect(database.readSyncState() == .init(cursor: "eyJ-opaque", historyBackfilled: true,
                                                  pendingClaimIDs: ["claim-missed"]),
                "the pending queue travels with the cursor — the only memory of failed card fetches")

        try database.clearSyncState()
        #expect(database.readSyncState() == .init(cursor: nil, historyBackfilled: false),
                "the sign-out boundary returns to a first sync")
    }
}
