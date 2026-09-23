import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension DeliveriesView {
    /// Pure presentation: the orders the device remembers, newest first — or one of two
    /// genuinely different empty states, so the branch is structure rather than
    /// show/hide of the same view (R9). The screen's one standing action — the prominent
    /// compose button (Design → "The tab bar goes") — stays available signed-out: a
    /// route can be drafted before a token exists; only pricing and ordering need the
    /// session.
    struct Content: View {
        /// One remembered order, reduced to its row. Status renders as the one chip —
        /// color, glyph and words together, never color alone.
        struct Row: Identifiable {
            let id: UUID
            let status: OrderStatus
            /// The route as remembered — `RouteLine`'s read of the order, badges and
            /// contacts included (board `3e`). Thin synced claims may carry fewer
            /// than two points; the line draws what exists.
            let route: [RoutePoint]
            let dateText: String
            let priceText: String?
        }

        let isSignedIn: Bool
        let rows: [Row]
        /// Why history is missing, when it is missing for a reason rather than because
        /// nothing was sent. An unreadable store rendered as "No deliveries yet", which
        /// tells a sender with a year of orders that they have none (review, PR #22).
        var historyUnavailable: String? = nil
        /// Why the rows may be stale — a sync failure renders beside history, never
        /// instead of it: what the device remembers is still worth reading.
        var syncError: String? = nil
        /// The pull-to-refresh ask — the root forwards it to the sync engine.
        var refresh: () async -> Void = {}
        let compose: () -> Void
        /// «Повторить»/«Наоборот» — the row's order id and whether the route runs
        /// backwards; the root turns it into a pre-filled draft (board `3e`).
        var repeatOrder: (Row.ID, _ reversed: Bool) -> Void = { _, _ in }

        var body: some View {
            Group {
                if !rows.isEmpty {
                    List {
                        ForEach(rows) { row in
                            NavigationLink(value: row.id) {
                                OrderRow(row: row)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    repeatOrder(row.id, false)
                                } label: {
                                    Label("Repeat", systemSymbol: .arrowClockwise)
                                }
                                Button {
                                    repeatOrder(row.id, true)
                                } label: {
                                    Label("Reverse", systemSymbol: .arrowUturnLeft)
                                }
                                .tint(.gray)
                            }
                        }
                        if let syncError {
                            Text(syncError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .refreshable { await refresh() }
                } else if let historyUnavailable {
                    // Checked before the empty states: *could not look* is not *nothing
                    // there*, and only this branch knows the difference.
                    ContentUnavailableView {
                        Label("Deliveries can't be read", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(historyUnavailable)
                    }
                } else if !isSignedIn {
                    ContentUnavailableView {
                        Label("Sign in to start", systemSymbol: .key)
                    } description: {
                        Text("Add your Yandex Delivery OAuth token in Settings.")
                    }
                } else if let syncError {
                    // The wire version of the branch above: a failed first sync on an
                    // empty store must not wear the "No deliveries yet" face — *could
                    // not check* is not *nothing there* (review, PR #35).
                    ContentUnavailableView {
                        Label("Deliveries can't be checked", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(syncError)
                    } actions: {
                        Button("Try again") { Task { await refresh() } }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No deliveries yet", systemSymbol: .shippingbox)
                    } description: {
                        Text("Orders you create will appear here, and stay here.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: compose) {
                    Label("New Delivery", systemSymbol: .plus)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, Layout.Spacing.unit)
            }
        }
    }
}

extension DeliveriesView.Content {
    /// The `3e` history card: status and date over the whole route drawn as a
    /// connected line, the price closing it. The repeat asks ride the row's swipe
    /// actions — they belong to the order, not the card's surface.
    struct OrderRow: View {
        let row: Row

        var body: some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.chip) {
                HStack {
                    StatusChip(status: row.status)
                    Spacer()
                    Text(row.dateText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                RouteLine(points: row.route)
                    .font(.subheadline)
                if let priceText = row.priceText {
                    HStack {
                        Spacer()
                        Text(priceText)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.vertical, Layout.Spacing.tight)
        }
    }
}

#Preview("Orders") {
    NavigationStack {
        DeliveriesView.Content(
        isSignedIn: true,
        rows: [
            .init(
                id: UUID(),
                status: .searching,
                route: [
                    RoutePoint(
                        latitude: 55.7137, longitude: 37.6323,
                        address: "Москва, ул Москворечье, 6",
                        contactName: "Иван Петров", contactPhone: "+79123456789"
                    ),
                    RoutePoint(
                        latitude: 55.7133, longitude: 37.5856,
                        address: "Москва, Каширское шоссе, 52"
                    ),
                ],
                dateText: "6 Sep, 11:40",
                priceText: "1 190 ₽"
            ),
            .init(
                id: UUID(),
                status: .done,
                route: [
                    RoutePoint(
                        latitude: 59.9311, longitude: 30.3609,
                        address: "Санкт-Петербург, Невский проспект, 100"
                    ),
                    RoutePoint(
                        latitude: 55.7558, longitude: 37.6173,
                        address: "Москва, Тверская, 6"
                    ),
                    RoutePoint(
                        latitude: 55.7495, longitude: 37.5938,
                        address: "Москва, Арбат, 10"
                    ),
                ],
                dateText: "4 Sep",
                priceText: "3 400 ₽"
            ),
        ],
        compose: {}
        )
    }
}

#Preview("Signed in, empty") {
    DeliveriesView.Content(isSignedIn: true, rows: [], compose: {})
}

#Preview("Sync failed, empty") {
    DeliveriesView.Content(
        isSignedIn: true,
        rows: [],
        syncError: "The provider could not be reached.",
        compose: {}
    )
}

#Preview("Signed out") {
    DeliveriesView.Content(isSignedIn: false, rows: [], compose: {})
}
