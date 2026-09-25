import Foundation
import YandexDeliveryExpressAPI
import YDeliveryKit

// The ordering lifecycle — create, watch, accept — and the mappings around it. Generated
// types live and die in this file (CLAUDE.md rule 1); the draft hands in its own
// vocabulary and gets back a placed ``PlacedClaim``.

extension ClientController {
    /// Creates the claim. The idempotency token guards the retry the provider warns
    /// about: a 5xx retried under a fresh token can dispatch two couriers.
    func createClaim(_ order: OrderRequest, requestID: UUID) async throws -> PlacedClaim {
        guard let client else { throw OffersUnavailable() }
        let response = try await client.createClaim(.init(
            query: .init(requestId: requestID.uuidString),
            headers: .init(acceptLanguage: .ru),
            body: .json(Self.createRequest(for: order))
        ))
        return try Self.createdClaim(from: response)
    }

    /// The create answer's refusal half — a documented non-200 carries the provider's
    /// `{code, message}` («tariff not available», …), which the `.ok` accessor would
    /// bury at the call where the sender most needs the reason (YD-11).
    nonisolated static func createdClaim(
        from response: Operations.CreateClaim.Output
    ) throws -> PlacedClaim {
        switch response {
        case .ok(let ok):
            return PlacedClaim(try ok.body.json)
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

    /// One look at where the claim stands.
    func claimState(id: String) async throws -> PlacedClaim {
        guard let client else { throw OffersUnavailable() }
        let response = try await client.getClaimInfo(.init(
            query: .init(claimId: id),
            headers: .init(acceptLanguage: .ru)
        ))
        return try Self.claim(from: response)
    }

    /// The claim-info answer read the honest way — documented refusals carry the
    /// provider's `{code, message}`, which the `.ok` accessor would bury (PR #31's
    /// lesson on `offers(for:)`, applied where the cancel flow now also reads).
    nonisolated static func claim(
        from response: Operations.GetClaimInfo.Output
    ) throws -> PlacedClaim {
        PlacedClaim(try claimInfo(from: response))
    }

    /// The same read, keeping the whole card — the claims sync's discovery path
    /// needs route and price, not just where the claim stands.
    nonisolated static func claimInfo(
        from response: Operations.GetClaimInfo.Output
    ) throws -> Components.Schemas.ClaimResponse {
        switch response {
        case .ok(let ok):
            return try ok.body.json
        case .badRequest(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .unauthorized(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .notFound(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .tooManyRequests(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .internalServerError(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .undocumented(let statusCode, _):
            throw ProviderRefusal(message: nil, status: statusCode)
        }
    }

    /// Confirms the estimated claim — the moment money moves.
    func acceptClaim(id: String, version: Int) async throws -> PlacedClaim {
        guard let client else { throw OffersUnavailable() }
        let response = try await client.acceptClaim(.init(
            query: .init(claimId: id),
            headers: .init(acceptLanguage: .ru),
            body: .json(.init(version: Int64(version)))
        ))
        return try Self.acceptedClaim(from: response, version: version)
    }

    /// The accept answer's refusal half. Its 409 is the spec's version/state
    /// refusal — the provider's own sentence («заявка уже подтверждена», a stale
    /// `version`, …) is exactly what the unresolved flow needs to hear
    /// (YD-11).
    nonisolated static func acceptedClaim(
        from response: Operations.AcceptClaim.Output,
        version: Int
    ) throws -> PlacedClaim {
        switch response {
        case .ok(let ok):
            let accepted = try ok.body.json
            return PlacedClaim(
                id: accepted.id, version: version,
                status: .init(accepted.status), failureText: nil)
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

    /// The create request, flat and complete. The traps stay pinned by tests:
    /// coordinates `[lon, lat]`, centimetres to metres, the declared value as the wire's
    /// POSIX decimal string, roles to `source`/`destination`/`return`, door details into
    /// `porch`/`sfloor`/`sflat`/`door_code`, and the extension into
    /// `phone_additional_code` — never folded into the number.
    nonisolated static func createRequest(
        for order: OrderRequest
    ) -> Components.Schemas.ClaimCreateRequest {
        let pointID: (UUID?, _ fallback: Int) -> Int64 = { id, fallback in
            Int64(id.flatMap { candidate in
                order.points.firstIndex { $0.pointID == candidate }.map { $0 + 1 }
            } ?? fallback)
        }
        // The custom-field carriers resolve here — the substrate names the role,
        // this boundary picks the wire slot (board `4b`): the claim's document,
        // the sender's own order number on every destination, the per-item tag.
        // Each slot admits one claimant — the store already refused a second.
        let claimDocument = order.fieldEntries.first {
            $0.definition.carrier == .claimDocument
        }?.value
        let orderNumber = order.fieldEntries.first {
            $0.definition.carrier == .orderNumber
        }?.value
        let itemTag = order.fieldEntries.first {
            $0.definition.carrier == .itemTag
        }?.value
        return .init(
            items: order.items.map { Self.wireItem(
                $0, pointID: pointID, lastPoint: order.points.count, itemTag: itemTag) },
            routePoints: order.points.enumerated().map {
                Self.wirePoint($1, at: $0, orderNumber: orderNumber)
            },
            clientRequirements: .init(
                taxiClass: order.tariffWireValue.flatMap(Components.Schemas.TaxiClass.init(rawValue:)) ?? .courier,
                cargoLoaders: order.options.loaders > 0 ? order.options.loaders : nil,
                cargoOptions: order.options.thermobag ? [.thermobag] : nil,
                proCourier: order.options.proCourier ? true : nil
            ),
            comment: order.options.comment.wireTrimmed,
            due: order.options.due,
            offerPayload: order.offerPayload,
            shippingDocument: claimDocument,
            skipDoorToDoor: order.options.toDoor ? nil : true
        )
    }

    private nonisolated static func wireItem(
        _ item: ParcelItem,
        pointID: (UUID?, Int) -> Int64,
        lastPoint: Int,
        itemTag: String? = nil
    ) -> Components.Schemas.CargoItem {
        let currency: Components.Schemas.Currency = .init(rawValue: item.currency) ?? .rub
        let cost: String = Self.wireDecimal(item.cost ?? 0)
        let size: Components.Schemas.ItemSize? = item.size.map { size in
            let metres: [Double] = [size.lengthCm / 100, size.widthCm / 100, size.heightCm / 100]
            return .init(length: metres[0], width: metres[1], height: metres[2])
        }
        return .init(
            costCurrency: currency,
            costValue: cost,
            pickupPoint: pointID(item.pickupPointID, 1),
            quantity: item.quantity,
            title: item.name,
            dropoffPoint: pointID(item.dropoffPointID, lastPoint),
            extraId: itemTag,
            size: size,
            weight: item.weightKg
        )
    }

    private nonisolated static func wirePoint(
        _ point: OrderRequest.Point,
        at index: Int,
        orderNumber: String? = nil
    ) -> Components.Schemas.RoutePointBase {
        let coordinates: [Double] = [point.longitude, point.latitude]
        let address = Components.Schemas.Address(
            fullname: point.address,
            building: point.parts?.building.wireTrimmed,
            coordinates: coordinates,
            doorCode: point.parts?.intercom.wireTrimmed,
            porch: point.parts?.entrance.wireTrimmed,
            sflat: point.parts?.apartment.wireTrimmed,
            sfloor: point.parts?.floor.wireTrimmed
        )
        let contact = Components.Schemas.Contact(
            name: point.contact.fullName,
            phone: point.contact.phone,
            phoneAdditionalCode: point.contact.phoneExtension.wireTrimmed
        )
        return .init(
            address: address,
            contact: contact,
            pointId: Int64(index + 1),
            _type: .init(point.role),
            visitOrder: index + 1,
            // The spec is explicit: `external_order_id` rides destination points —
            // the sender's own order number the courier's flow and `claims/search`
            // both key on. Pickup and return legs don't take it.
            externalOrderId: point.role == .dropoff ? orderNumber : nil
        )
    }

    /// Money on the wire is a POSIX decimal string — never the locale's comma.
    nonisolated static func wireDecimal(_ value: Decimal) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...2))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}

/// Everything a create call needs, in the draft's vocabulary.
nonisolated struct OrderRequest: Hashable, Sendable {
    var points: [Point]
    private(set) var items: [ParcelItem]
    /// «Ваши поля» answers that filled the draft — definition + value, so the
    /// mapping can read the carrier each value rides (board `4b`).
    var fieldEntries: [FieldEntry]
    var options: DeliveryOptions
    var offerPayload: String?
    var tariffWireValue: String?

    /// Item stops are normalised against these points on the way in, exactly as
    /// ``OfferRequest`` does it: an id naming no point here becomes `nil`. That keeps
    /// the mapping's `nil` meaning one thing — the route's ends — rather than either
    /// that *or* a stop that was deleted. On the create call the stakes are higher than
    /// on pricing: this is the request that dispatches a courier (review, PR #22).
    init(
        points: [Point],
        items: [ParcelItem],
        fieldEntries: [FieldEntry] = [],
        options: DeliveryOptions,
        offerPayload: String? = nil,
        tariffWireValue: String? = nil
    ) {
        self.points = points
        self.fieldEntries = fieldEntries
        self.options = options
        self.offerPayload = offerPayload
        self.tariffWireValue = tariffWireValue
        let live = Set(points.map(\.pointID))
        self.items = items.map { item in
            var item = item
            if let id = item.pickupPointID, !live.contains(id) { item.pickupPointID = nil }
            if let id = item.dropoffPointID, !live.contains(id) { item.dropoffPointID = nil }
            return item
        }
    }

    /// One stop, complete: where, how spelled, who answers the door.
    nonisolated struct Point: Hashable, Sendable {
        var pointID: UUID
        var latitude: Double
        var longitude: Double
        var address: String
        var parts: AddressParts?
        var contact: Contact
        var role: NewDeliveryView.Model.Role
    }

    /// A filled field with its definition — the carrier lives on the definition,
    /// so the value alone could not say which wire slot it claims.
    nonisolated struct FieldEntry: Hashable, Sendable {
        var definition: CustomFieldDefinition
        var value: String
    }
}

/// Where a placed claim stands, in the sender's terms — plus what the wire needs to move
/// it forward.
nonisolated struct PlacedClaim: Hashable, Sendable {
    var id: String
    var version: Int
    var status: Progress
    /// The provider's own words when estimation failed — displayable as arrived.
    var failureText: String?

    nonisolated enum Progress: Hashable, Sendable {
        /// Still pricing the run.
        case estimating
        /// Priced — accepting is what moves money.
        case readyToAccept
        /// Accepted; the courier search runs.
        case searching
        /// The provider could not price or place the run.
        case failed
        /// A state this app does not know yet — polling keeps waiting, honestly.
        case other(String)
    }
}

nonisolated extension PlacedClaim {
    init(_ claim: Components.Schemas.ClaimResponse) {
        self.init(
            id: claim.id,
            version: Int(claim.version),
            status: .init(claim.status),
            failureText: claim.errorMessages?.compactMap(\.message).first
        )
    }
}

nonisolated extension PlacedClaim.Progress {
    /// Every wire status that means "closed by cancellation" shares the `cancelled`
    /// prefix — and all of them land in `.other`, the zoo's honest bucket.
    var isCancelled: Bool {
        if case .other(let raw) = self { return raw.hasPrefix("cancelled") }
        return false
    }

    /// The wire's status zoo, collapsed to what the ordering flow decides on. Anything
    /// past `accepted` means the search (or more) is running — the draft's job is done.
    init(_ status: Components.Schemas.ClaimStatus) {
        self = switch status {
        case .new, .estimating: .estimating
        case .readyForApproval: .readyToAccept
        case .estimatingFailed, .failed: .failed
        case .accepted, .performerLookup, .performerDraft, .performerFound: .searching
        default: .other(status.rawValue)
        }
    }
}

nonisolated extension TariffClass {
    /// The wire spelling `client_requirements.taxi_class` wants back.
    var wireValue: String {
        switch self {
        case .courier: "courier"
        case .express: "express"
        case .cargo: "cargo"
        case .other(let raw): raw
        }
    }

    /// The inverse of ``wireValue``: what the store remembered as `order.tariff`,
    /// back as vocabulary «Повторить» can re-offer. An unknown spelling keeps its
    /// name rather than collapsing to a guess — the same policy `.other` sets.
    init(wireSpelling: String) {
        self = switch wireSpelling {
        case "courier": .courier
        case "express": .express
        case "cargo": .cargo
        default: .other(wireSpelling)
        }
    }
}

nonisolated extension Components.Schemas.PointType {
    init(_ role: NewDeliveryView.Model.Role) {
        self = switch role {
        case .pickup: .source
        case .dropoff: .destination
        case .return: ._return
        }
    }
}

private nonisolated extension String {
    /// Trimmed, and absent when nothing remains — the wire stores what exists.
    var wireTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
