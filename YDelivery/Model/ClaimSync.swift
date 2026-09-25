import Foundation
import YandexDeliveryExpressAPI
import YDeliveryKit

// The wire→app mapping the claims list runs on — generated schemas enter here and
// never leave (CLAUDE.md rule 1's model side). `PlacedClaim.Progress` keeps answering
// for the ordering flow; this file owns the *history* vocabulary: the whole status
// zoo collapsed into the sender's six states, plus the pure merge functions the sync
// engine applies — each one a total function on `[Order]`, so the tests read like
// the spec they pin.

/// The journal position the provider stopped honouring (`invalid_cursor`) — the one
/// refusal that means "replay from the beginning", not "show the user".
nonisolated struct JournalCursorInvalid: LocalizedError, Hashable {
    var errorDescription: String? {
        String(localized: "The saved sync position is no longer valid — history will re-sync from the beginning.")
    }
}

/// A pass ran out of pages with a cursor still live — membership beyond the cap is
/// real and still unfetched. Reported, never silent: rows that *are* synced stay,
/// and the sender sees why the list may be short (review, PR #35). The deferred
/// deep replay (`BGProcessingTask`, Wi-Fi + charger) owns the unbounded case.
nonisolated struct SyncIncomplete: LocalizedError, Hashable {
    var errorDescription: String? {
        String(localized: "More deliveries exist than one sync could page — history is partial until a deep sync.")
    }
}

/// The pure half of the claims sync: events and searched claims folded into history,
/// nothing awaited, nothing thrown. The controller owns the wire; these own the merge.
nonisolated enum ClaimsSync {
    /// Claim ids the journal reports that history does not know — the discovery half
    /// of the feed. A claim that changed but was never recorded here (another device,
    /// a claim predating the cursor, an acceptance lost to a timeout) is fetched
    /// whole rather than skipped.
    static func missingClaimIDs(
        in events: [Components.Schemas.JournalEvent],
        among orders: [Order]
    ) -> [String] {
        let known = Set(orders.compactMap(\.claimID))
        var seen = Set<String>()
        return events.map(\.claimId).filter { !known.contains($0) && seen.insert($0).inserted }
    }

    /// One journal event folded into the orders it touches. Every event sets an
    /// absolute state — replay is idempotent, which is what lets the cursor persist
    /// only *after* the page lands. An event for a claim history doesn't know is a
    /// no-op here; the caller fetches the card.
    static func applying(
        _ event: Components.Schemas.JournalEvent,
        to orders: [Order]
    ) -> [Order] {
        guard let index = orders.firstIndex(where: { $0.claimID == event.claimId }) else {
            return orders
        }
        var orders = orders
        switch event.changeType {
        case .statusChanged:
            if let status = event.newStatus {
                orders[index].status = OrderStatus(claimStatus: status)
            }
        case .priceChanged:
            if let price = event.newPrice { orders[index].price = price }
            if let currency = event.newCurrency { orders[index].currency = currency }
        }
        return orders
    }

    /// Searched claims merged into history by `claimID`: a known claim updates in
    /// place — keeping its local id, so a row's identity never moves under the
    /// sender — while an unknown claim becomes a new order. A page that repeats
    /// a claim keeps its *newest* card — the same winner `stamps` reports, or
    /// the row would carry a freshness its content never earned and refuse its
    /// own correction (review, PR #43); equal stamps keep the last arrival.
    /// The result stays newest-first, the store's standing order.
    static func merging(
        _ claims: [Components.Schemas.ClaimResponse],
        into orders: [Order]
    ) -> [Order] {
        var newest: [String: Components.Schemas.ClaimResponse] = [:]
        for claim in claims
        where newest[claim.id].map({ $0.updatedTs > claim.updatedTs }) != true {
            newest[claim.id] = claim
        }
        var orders = orders
        for claim in newest.values {
            let order = Order(
                claim: claim,
                adoptingID: orders.first(where: { $0.claimID == claim.id })?.id ?? UUID()
            )
            orders.removeAll { $0.id == order.id }
            orders.append(order)
        }
        return orders.sorted { $0.created > $1.created }
    }

    /// Provider-side as-of stamps for a page of claims — `updatedTs` per
    /// claimID. The mirror's freshness follows the provider's clock, not the
    /// read's: this is what `recordOrder(providerObservedAt:)` receives.
    static func stamps(
        of claims: [Components.Schemas.ClaimResponse]
    ) -> [String: Date] {
        Dictionary(claims.map { ($0.id, $0.updatedTs) },
                   uniquingKeysWith: { Swift.max($0, $1) })
    }

    /// A feed event as the feed's own row (`providerEvents`, doc:Schema): the
    /// journal's `operationId` is the dedupe key, so a replayed page re-derives
    /// the same row and `recordProviderEvent` answers "new to us". `at` is the
    /// event's own stamp — provider time is what the mirror's freshness gate
    /// compares, never the read's clock.
    static func providerEvent(
        _ event: Components.Schemas.JournalEvent,
        orderID: Order.ID
    ) -> ProviderEvent {
        ProviderEvent(
            orderID: orderID,
            providerEventID: event.operationId,
            at: event.updatedTs,
            kind: event.changeType.rawValue,
            providerStatus: event.newStatus?.rawValue,
            detail: detail(of: event),
            source: "journal"
        )
    }

    /// A claim observed outside the feed — a search page or a fetched card — as
    /// the id-less half of the event stream. `at` is the claim's own `updatedTs`,
    /// the as-of time its content describes: a delayed answer can't rewind the
    /// mirror past a journal event it predates. The derived key
    /// (`orderID ‖ status ‖ source`) makes the hundredth sighting of the same
    /// status merge into its first row — while still freshening the mirror's
    /// observation stamp.
    static func sighting(
        of claim: Components.Schemas.ClaimResponse,
        orderID: Order.ID,
        source: String
    ) -> ProviderEvent {
        ProviderEvent(
            orderID: orderID,
            at: claim.updatedTs,
            kind: "sighting",
            providerStatus: claim.status.rawValue,
            source: source
        )
    }

    /// The event's payload as one detail string: a status change carries the
    /// terminal `resolution` when it has one (`success`/`failed`); a price
    /// change carries the new figure with its currency.
    private static func detail(of event: Components.Schemas.JournalEvent) -> String? {
        switch event.changeType {
        case .statusChanged:
            return event.resolution?.rawValue
        case .priceChanged:
            let joined = [event.newPrice, event.newCurrency]
                .compactMap { $0 }
                .joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
    }
}

nonisolated extension OrderStatus {
    /// The wire's claim lifecycle collapsed into the sender's six states — the
    /// vocabulary YD-7 waited for. The distinction that matters to a list row is
    /// *who must act*: statuses where only the provider moves are `searching` or
    /// `active`; statuses parked on the sender's decision — accept the estimate,
    /// retry a failed search, pay, decide about a returned parcel — are `attention`,
    /// never a raw wire word.
    init(claimStatus: Components.Schemas.ClaimStatus) {
        self = switch claimStatus {
        case .new, .estimating,
             .accepted, .performerLookup, .performerDraft:
            .searching
        case .performerFound, .pickupArrived, .readyForPickupConfirmation,
             .pickuped, .deliveryArrived, .readyForDeliveryConfirmation,
             .returning, .returnArrived, .readyForReturnConfirmation:
            .active
        case .delivered, .deliveredFinish:
            .done
        case .cancelled, .cancelledWithPayment, .cancelledByTaxi,
             .cancelledWithItemsOnHands:
            .cancelled
        case .readyForApproval, .estimatingFailed, .performerNotFound,
             .payWaiting, .failed,
             .returned, .returnedFinish:
            .attention
        }
    }
}

nonisolated extension Order {
    /// A provider claim as a history row. `adoptingID` keeps a stored order's local
    /// identity when the claim updates it — the row's content moves, its id never
    /// does. The wire's `return` point is kept on purpose: this app *sends* its
    /// drop-off as `return` (see `createRequest`), so the wire's last stop is the
    /// sender's destination, not courier bookkeeping.
    ///
    /// The courier line and ETA ride the sighting too — `performer_info` and `eta`
    /// are the widget/Live Activity's «who to call» and «when», and the mirror
    /// overwrites them with each fresher sighting: a claim reporting no courier
    /// clears the name a previous one left.
    init(claim: Components.Schemas.ClaimResponse, adoptingID id: UUID) {
        let performer = claim.performerInfo
        let vehicle = [performer?.carModel, performer?.carNumber]
            .compactMap { $0 }
            .joined(separator: " ")
        self.init(
            id: id,
            created: claim.createdTs,
            status: OrderStatus(claimStatus: claim.status),
            route: claim.routePoints
                .sorted { $0.visitOrder < $1.visitOrder }
                .map(RoutePoint.init(claimPoint:)),
            price: claim.pricing?.finalPrice ?? claim.pricing?.offer?.priceWithVat,
            currency: claim.pricing?.currency?.rawValue,
            tariff: claim.clientRequirements?.taxiClass.rawValue,
            claimID: claim.id,
            courierName: performer.flatMap {
                $0.courierName.isEmpty ? nil : $0.courierName
            },
            courierVehicle: vehicle.isEmpty
                ? performer?.transportType
                : vehicle,
            etaMinutes: claim.eta.map(Int.init),
            providerStatus: claim.status.rawValue
        )
    }
}

nonisolated extension RoutePoint {
    /// A wire route point as the store remembers it: `[lon, lat]` back into fields,
    /// door details into `AddressParts`' own names, the extension never folded into
    /// the phone. `contact.name` stays whole — Cyrillic names do not split reliably,
    /// which is exactly why the name components were made explicit fields. The visit
    /// record rides verbatim — `visited_at.actual` is stamped only on visited stops,
    /// `expected` only while one still waits (the wire's own rule).
    init(claimPoint point: Components.Schemas.RoutePoint) {
        let coordinates = point.address.coordinates ?? []
        let parts = AddressParts(
            entrance: point.address.porch ?? "",
            floor: point.address.sfloor ?? "",
            apartment: point.address.sflat ?? "",
            intercom: point.address.doorCode ?? ""
        )
        self.init(
            latitude: coordinates.count > 1 ? coordinates[1] : 0,
            longitude: coordinates.count > 1 ? coordinates[0] : 0,
            address: point.address.fullname,
            addressParts: parts.isEmpty ? nil : parts,
            contactName: point.contact.name.isEmpty ? nil : point.contact.name,
            contactPhone: point.contact.phone.isEmpty ? nil : point.contact.phone,
            contactPhoneExtension: point.contact.phoneAdditionalCode,
            visit: PointVisitStatus(rawValue: point.visitStatus.rawValue)
                .map { status in
                    Visit(status: status,
                          visitedAt: point.visitedAt.actual,
                          expectedAt: point.visitedAt.expected)
                }
        )
    }
}
