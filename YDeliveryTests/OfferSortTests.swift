import Foundation
import Testing
@testable import YDelivery

/// The strip's order and the window words — the piece of an offer the price alone
/// never carried (the drive's wire log: four courier variants, four delivery ends).
@Suite("Offer sorting and windows")
struct OfferSortTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func offer(
        _ id: String, price: Decimal,
        deliveryEnd: Date? = nil, pickupEnd: Date? = nil,
        validUntil: Date? = nil
    ) -> Offer {
        Offer(tariff: .courier, price: price, currency: "RUB",
              pickupInterval: pickupEnd.map { $0 - 600 ... $0 },
              deliveryInterval: deliveryEnd.map { $0 - 600 ... $0 },
              validUntil: validUntil,
              payload: id)
    }

    @Test("Fastest orders by the delivery end — a windowless card sorts last")
    func fastestByDeliveryEnd() {
        let offers = [
            offer("none", price: 100),
            offer("late", price: 300, deliveryEnd: base + 3600),
            offer("soon", price: 900, deliveryEnd: base + 60),
        ]
        #expect(offers.sorted(by: .fastest).map(\.id) == ["soon", "late", "none"])
    }

    @Test("Fastest ties on the delivery end fall to the cheaper card")
    func fastestTiesByPrice() {
        let offers = [
            offer("dear", price: 900, deliveryEnd: base),
            offer("cheap", price: 300, deliveryEnd: base),
        ]
        #expect(offers.sorted(by: .fastest).map(\.id) == ["cheap", "dear"])
    }

    @Test("Cheapest orders by price — ties fall to the earlier delivery")
    func cheapestByPriceThenWindow() {
        let offers = [
            offer("slow", price: 300, deliveryEnd: base + 3600),
            offer("dear", price: 900, deliveryEnd: base + 60),
            offer("quick", price: 300, deliveryEnd: base + 60),
        ]
        #expect(offers.sorted(by: .cheapest).map(\.id) == ["quick", "slow", "dear"])
    }

    @Test("The window names the day only when the end is not today")
    func windowNamesOtherDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // `isDateInToday` reads *now*, so the fixture must be today's date —
        // eleven hours out stays inside the day on any sane wall clock except the
        // last hours of the date; anchor at noon instead of midnight.
        let today = calendar.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        let sameDay = today
        let otherDay = today.addingTimeInterval(24 * 3600)

        let same = Offer.windowEnd(sameDay, calendar: calendar)
        #expect(same == sameDay.formatted(.dateTime.hour().minute()),
                "same-day is a bare time")
        let other = Offer.windowEnd(otherDay, calendar: calendar)
        #expect(other == otherDay.formatted(.dateTime.day().month(.abbreviated).hour().minute()),
                "another day is dated, not a bare time")
    }

    @Test("The card's words wrap the window")
    func cardWords() {
        let end = Date.now.addingTimeInterval(3600)
        let card = offer("a", price: 749, deliveryEnd: end, pickupEnd: end - 1800)
        #expect(card.deliveryByText?.hasPrefix("by ") == true)
        #expect(card.pickupByText?.hasPrefix("pickup by ") == true)
        #expect(offer("b", price: 1).deliveryByText == nil,
                "no window is absence, not a broken line")
    }

    @Test("`offer_ttl` spent means expired; absent means timeless")
    func expiryReadsTheDeadline() {
        let stale = offer("a", price: 749, validUntil: Date.now - 60)
        #expect(stale.isExpired())
        #expect(!offer("b", price: 749, validUntil: Date.now + 600).isExpired())
        #expect(!offer("c", price: 749).isExpired(),
                "the wire saying nothing is not a deadline")
    }
}
