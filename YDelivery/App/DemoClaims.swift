import Foundation

/// The canned wire objects `DemoTransport` seeds and quotes — claim and journal
/// shapes mirroring `openapi.yaml` in `YandexDeliveryExpressAPI`, patterned on
/// the package's `SearchClaimsResponse`/`IntegrationV2Offers` live fixtures.
/// Values the app maps (`status`, `route_points`, `pricing`, `performer_info`)
/// follow the same field names the real responses carry. `nonisolated`: pure
/// builders the transport's actor calls — they must not inherit the module's
/// MainActor default.
nonisolated enum DemoClaims {
    /// A seeded claim plus its status trail — a labelled tuple, because a
    /// `struct`'s members would inherit the module's MainActor isolation.
    /// `operation_id` and `claim_id` are the transport's to mint — fixtures
    /// declare the rows, it numbers them.
    typealias Seed = (claim: [String: Any], events: [[String: Any]])

    // MARK: - Seeds

    /// «Courier on the way» — the live row: a `performer_found` claim with a
    /// named courier, ETA and a *paid* cancellation, so the reviewer sees the
    /// fee-confirming path in Cancel too.
    static func enRoute(now: Date) -> Seed {
        let created = now.addingTimeInterval(-3600)
        let found = now.addingTimeInterval(-1200)
        var claim = base(
            id: "demo0000000000000000000000000001",
            status: "performer_found",
            created: created, updated: found, revision: 6,
            taxiClass: "express", price: "890.00",
            items: [item(title: "Документы", cost: "500", pickup: 101, dropoff: 102)],
            points: [
                source(id: 101, visitOrder: 1,
                       address: "Москва, Никольская улица, 10",
                       coordinates: [37.6277, 55.7567],
                       name: "Ольга Соколова", phone: "+79161234567"),
                destination(id: 102, visitOrder: 2,
                            address: "Москва, Пятницкая улица, 25",
                            coordinates: [37.6290, 55.7425],
                            name: "Сергей Волков", phone: "+79269876543",
                            expectedAt: now.addingTimeInterval(1800)),
            ],
            currentPointID: 101,
            due: now.addingTimeInterval(-2400))
        claim["eta"] = 15
        claim["performer_info"] = performer
        claim["available_cancel_state"] = "paid"
        return Seed(claim: claim, events: trail([
            ("new", created), ("estimating", created.advanced(by: 60)),
            ("ready_for_approval", created.advanced(by: 300)),
            ("accepted", created.advanced(by: 600)),
            ("performer_lookup", created.advanced(by: 660)),
            ("performer_found", found),
        ], pointID: 101))
    }

    /// «Delivered» — the done row: both visits stamped `visited`, the full
    /// lifecycle in its trail, priced cheaper on the `courier` class.
    static func delivered(now: Date) -> Seed {
        let created = now.addingTimeInterval(-93600) // yesterday +2h
        let done = now.addingTimeInterval(-86400)
        var claim = base(
            id: "demo0000000000000000000000000002",
            status: "delivered",
            created: created, updated: done, revision: 10,
            taxiClass: "courier", price: "640.00",
            items: [item(title: "Подарок", cost: "2200", pickup: 201, dropoff: 202)],
            points: [
                source(id: 201, visitOrder: 1,
                       address: "Москва, Тверская улица, 7",
                       coordinates: [37.6090, 55.7600],
                       name: "Марина Ким", phone: "+79165550101",
                       visited: true, at: created.advanced(by: 4200)),
                destination(id: 202, visitOrder: 2,
                            address: "Москва, улица Арбат, 44",
                            coordinates: [37.5930, 55.7500],
                            name: "Дмитрий Орлов", phone: "+79165550202",
                            visited: true, at: done),
            ],
            currentPointID: 202,
            due: created.advanced(by: 1200))
        claim["performer_info"] = performer
        claim["available_cancel_state"] = "none"
        return Seed(claim: claim, events: trail([
            ("new", created), ("estimating", created.advanced(by: 60)),
            ("ready_for_approval", created.advanced(by: 240)),
            ("accepted", created.advanced(by: 900)),
            ("performer_lookup", created.advanced(by: 960)),
            ("performer_found", created.advanced(by: 1500)),
            ("pickup_arrived", created.advanced(by: 3900)),
            ("pickuped", created.advanced(by: 4200)),
            ("delivery_arrived", created.advanced(by: 6900)),
            ("delivered", done),
        ], pointID: 202))
    }

    /// «Needs a decision» — the attention row: `performer_not_found`, the
    /// terminal-unmatched state the wire finishes on when nobody takes the run.
    static func unclaimed(now: Date) -> Seed {
        let created = now.addingTimeInterval(-10800)
        let failed = now.addingTimeInterval(-8400)
        var claim = base(
            id: "demo0000000000000000000000000003",
            status: "performer_not_found",
            created: created, updated: failed, revision: 3,
            taxiClass: "express", price: "1139.00",
            items: [item(title: "Запчасть", cost: "3400", pickup: 301, dropoff: 302)],
            points: [
                source(id: 301, visitOrder: 1,
                       address: "Москва, Ленинский проспект, 38",
                       coordinates: [37.5853, 55.7075],
                       name: "Игорь Панов", phone: "+79165550303"),
                destination(id: 302, visitOrder: 2,
                            address: "Москва, Профсоюзная улица, 108",
                            coordinates: [37.5410, 55.6640],
                            name: "Анна Литвинова", phone: "+79165550404"),
            ],
            currentPointID: 301,
            due: created.advanced(by: 600))
        claim["available_cancel_state"] = "none"
        return Seed(claim: claim, events: trail([
            ("new", created), ("estimating", created.advanced(by: 60)),
            ("performer_not_found", failed),
        ], pointID: 301))
    }

    // MARK: - Offers

    /// Three tariff cards — `courier`, `express`, `superexpress_d2d` — priced
    /// and windowed relative to *now* so an offer never reads expired; the
    /// create echoes `payload` back, which the demo ignores.
    static func offers() -> [String: Any] {
        let now = Date.now
        return ["offers": [
            offer(class: "courier", price: "890.00", now: now,
                  pickup: (600, 1500), delivery: (3600, 7200)),
            offer(class: "express", price: "1240.00", now: now,
                  pickup: (300, 900), delivery: (1800, 4200)),
            offer(class: "superexpress_d2d", price: "1690.00", now: now,
                  pickup: (120, 600), delivery: (900, 2400)),
        ]]
    }

    private static func offer(
        class taxiClass: String, price: String, now: Date,
        pickup: (TimeInterval, TimeInterval),
        delivery: (TimeInterval, TimeInterval)
    ) -> [String: Any] {
        [
            "offer_id": "demo-offer-\(taxiClass)",
            "taxi_class": taxiClass,
            "payload": "demo-\(taxiClass)",
            "price": [
                "total_price": price,
                "total_price_with_vat": price,
                "surge_ratio": 1.0,
                "currency": "RUB",
                "currency_rules": currencyRules,
                "offer": [
                    "offer_id": "demo-offer-\(taxiClass)",
                    "price_raw": price,
                    "price": price,
                ],
            ],
            "pickup_interval": [
                "from": timestamp(now.addingTimeInterval(pickup.0)),
                "to": timestamp(now.addingTimeInterval(pickup.1)),
            ],
            "delivery_interval": [
                "from": timestamp(now.addingTimeInterval(delivery.0)),
                "to": timestamp(now.addingTimeInterval(delivery.1)),
            ],
            "offer_ttl": timestamp(now.addingTimeInterval(600)),
            "client_requirements": [
                "taxi_class": taxiClass, "cargo_loaders": 0,
                "cargo_options": [String](), "pro_courier": false,
            ],
            "available_cancel_state": "free",
        ]
    }

    /// The price a created claim carries, consistent with the offers for the
    /// same class so the order's figure matches the tariff the reviewer picked.
    static func price(forTaxiClass taxiClass: String) -> String {
        switch taxiClass {
        case "courier": "890.00"
        case "express": "1240.00"
        case "cargo": "2600.00"
        case "superexpress_d2d": "1690.00"
        default: "1240.00"
        }
    }

    // MARK: - Shared building blocks

    /// `search` bucketing, per `SearchClaimState`'s observed split: `finished`
    /// holds every status a claim can end on — delivered, cancelled, returned,
    /// failed, unmatched — `delayed` the unpaid-wait, `active` the rest.
    static let finishedStatuses: Set<String> = [
        "delivered", "delivered_finish", "cancelled", "cancelled_with_payment",
        "cancelled_by_taxi", "cancelled_with_items_on_hands",
        "returned", "returned_finish", "failed", "estimating_failed",
        "performer_not_found",
    ]
    static let delayedStatuses: Set<String> = ["pay_waiting"]

    static var performer: [String: Any] { [
        "courier_name": "Алексей Смирнов",
        "legal_name": "ООО Доставка",
        "transport_type": "bike",
    ] }
    static var emergencyContact: [String: Any] { [
        "name": "Demo Support", "phone": "+78000000000",
        "phone_additional_code": "",
    ] }
    static var currencyRules: [String: Any] { [
        "code": "RUB", "text": "руб.", "template": "$VALUE$ руб.", "sign": "руб.",
    ] }

    static func pricing(total: String) -> [String: Any] {
        [
            "final_price": total,
            "currency": "RUB",
            "currency_rules": currencyRules,
            "surge_ratio": 1.0,
            "offer": [
                "offer_id": "demo-offer",
                "price_raw": total,
                "price": total,
            ],
        ]
    }

    /// A claim object minus the per-seed extras — the fields `Order(claim:)`
    /// reads plus the ones the wire always carries.
    private static func base(
        id: String, status: String, created: Date, updated: Date,
        revision: Int, taxiClass: String, price: String,
        items: [[String: Any]], points: [[String: Any]],
        currentPointID: Int, due: Date
    ) -> [String: Any] {
        [
            "id": id,
            "corp_client_id": "demo",
            "status": status,
            "version": 1,
            "revision": revision,
            "user_request_revision": "1",
            "created_ts": timestamp(created),
            "updated_ts": timestamp(updated),
            "last_status_change_ts": timestamp(updated),
            "route_points": points,
            "items": items,
            "current_point_id": currentPointID,
            "client_requirements": [
                "taxi_class": taxiClass, "cargo_loaders": 0,
                "cargo_options": [String](), "pro_courier": false,
            ],
            "due": timestamp(due),
            "comment": "",
            "skip_door_to_door": false,
            "skip_client_notify": false,
            "optional_return": false,
            "same_day_data": [
                "delivery_interval": [
                    "from": timestamp(due),
                    "to": timestamp(due.addingTimeInterval(3600)),
                ],
            ],
            "pricing": pricing(total: price),
            "emergency_contact": emergencyContact,
            "error_messages": [String](),
        ]
    }

    private static func item(
        title: String, cost: String, pickup: Int, dropoff: Int
    ) -> [String: Any] {
        [
            "cost_currency": "RUB", "cost_value": cost,
            "pickup_point": pickup, "dropoff_point": dropoff,
            "quantity": 1, "title": title, "weight": 0.2,
            "size": ["height": 0.05, "length": 0.3, "width": 0.22],
        ]
    }

    /// A route point; `visited` stamps `visited_at.actual` for a completed
    /// stop, `expected` the one timestamp a pending one still waits behind —
    /// the schema's `PointVisitTime` carries single date-times, not intervals.
    /// Absent keys stay absent — an `Optional` boxed into `Any` is the one
    /// value `JSONSerialization` refuses.
    private static func point(
        id: Int, type: String, visitOrder: Int,
        address: String, coordinates: [Double],
        name: String, phone: String,
        visited: Bool, at visitedAt: Date?,
        expectedAt: Date?
    ) -> [String: Any] {
        var visit: [String: Any] = [:]
        if !visited, let expectedAt { visit["expected"] = timestamp(expectedAt) }
        if let visitedAt { visit["actual"] = timestamp(visitedAt) }
        return [
            "id": id,
            "type": type,
            "visit_order": visitOrder,
            "visit_status": visited ? "visited" : "pending",
            "visited_at": visit,
            "address": [
                "fullname": address,
                "coordinates": coordinates,
                "city": "Москва",
                "country": "Россия",
                "building": "", "porch": "", "sflat": "", "sfloor": "",
                "door_code": "", "description": "",
            ],
            "contact": [
                "name": name, "phone": phone, "phone_additional_code": "",
            ],
            "external_order_id": "",
        ]
    }

    private static func source(
        id: Int, visitOrder: Int, address: String, coordinates: [Double],
        name: String, phone: String,
        visited: Bool = false, at visitedAt: Date? = nil
    ) -> [String: Any] {
        point(id: id, type: "source", visitOrder: visitOrder,
              address: address, coordinates: coordinates,
              name: name, phone: phone,
              visited: visited, at: visitedAt, expectedAt: nil)
    }

    private static func destination(
        id: Int, visitOrder: Int, address: String, coordinates: [Double],
        name: String, phone: String,
        visited: Bool = false, at visitedAt: Date? = nil,
        expectedAt: Date? = nil
    ) -> [String: Any] {
        point(id: id, type: "destination", visitOrder: visitOrder,
              address: address, coordinates: coordinates,
              name: name, phone: phone,
              visited: visited, at: visitedAt, expectedAt: expectedAt)
    }

    /// `(status, at)` pairs expanded into journal rows — `status_changed`,
    /// the trail the wire grows under a claim. `claim_id` and `operation_id`
    /// are the transport's to mint, so they are not set here.
    private static func trail(
        _ statuses: [(String, Date)], pointID: Int
    ) -> [[String: Any]] {
        statuses.enumerated().map { index, entry in
            [
                "change_type": "status_changed",
                "new_status": entry.0,
                "updated_ts": timestamp(entry.1),
                "revision": index + 1,
                "current_point_id": pointID,
            ]
        }
    }

    /// `FlexibleISO8601Transcoder` accepts both `Z` and `+00:00`; the
    /// formatter's Zulu output is what the offers fixture already carries.
    private static var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func timestamp(_ date: Date) -> String {
        iso8601.string(from: date)
    }
}
