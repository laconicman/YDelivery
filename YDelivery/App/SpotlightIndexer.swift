import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers
import YDeliveryKit

/// The board's promise: typing «4417» in Spotlight finds the delivery (board `4b`).
/// History is indexed from the store, never from the wire — a delivery outlives the
/// vendor's visibility window, and the index is just another reader of it.
///
/// App-side because indexing renders *this* app's vocabulary — what counts as the
/// searchable identity, the route summary — on top of the shared store. Tapping a
/// result hands the order id back through `CSSearchableItemActionType`;
/// `DeliveriesView` pushes the matching row.
nonisolated enum SpotlightIndexer {
    /// One domain for all order items — reindexing wipes it and re-adds, so a
    /// vanished order cannot haunt search (history is append-mostly, but a
    /// cancelled row's cleanup or a fresh install must not ghost).
    private static let domain = "orders"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "spotlight")

    /// Reconciles the index with the store: wipe the domain, re-add the current
    /// set. Called after each orders read; cheap at history scale, and Spotlight is
    /// best-effort — a failure is logged, never surfaced.
    static func reindex(orders: [Order], fields: [OrderCustomField]) async {
        let index = CSSearchableIndex.default()
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
            let items = orders.map { item(for: $0, fields: fields) }
            try await index.indexSearchableItems(items)
        } catch {
            logger.error("Spotlight reindex failed: \(error.localizedDescription)")
        }
    }

    /// One order → one searchable item. The sender's own order number (the field
    /// riding the `orderNumber` carrier, when configured) is the title — it outranks
    /// the provider claim id on every surface, the index included; the rest of the
    /// values are keywords, matching "searchable by their values" verbatim. The
    /// carrier reads off the value's own snapshot — the definitions are
    /// private-tier, so a collaborator's index has nothing to join (YD-17).
    private static func item(for order: Order, fields: [OrderCustomField])
        -> CSSearchableItem {
        let own = fields.filter { $0.orderID == order.id }
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        let orderNumber = own.first { $0.carrier == .orderNumber }?.value
        attributes.title = orderNumber.map { String(localized: "Order \($0)") }
            ?? order.routeSummary
        attributes.contentDescription = order.routeSummary
        attributes.keywords = own.map(\.value) + order.route.map(\.address)
        return CSSearchableItem(
            uniqueIdentifier: order.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
    }
}

private nonisolated extension Order {
    /// «Тверская, 6 → Невский, 100» — the two ends, or as many as fit one line.
    var routeSummary: String {
        route.map(\.address).filter { !$0.isEmpty }.joined(separator: " → ")
    }
}
