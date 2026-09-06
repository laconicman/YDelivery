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
            let from: String
            let to: String
            let dateText: String
            let priceText: String?
        }

        let isSignedIn: Bool
        let rows: [Row]
        let compose: () -> Void

        var body: some View {
            Group {
                if !rows.isEmpty {
                    List(rows) { row in
                        OrderRow(row: row)
                    }
                } else if isSignedIn {
                    ContentUnavailableView {
                        Label("No deliveries yet", systemSymbol: .shippingbox)
                    } description: {
                        Text("Orders you create will appear here, and stay here.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("Sign in to start", systemSymbol: .key)
                    } description: {
                        Text("Add your Yandex Delivery OAuth token in Settings.")
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
    /// The minimal honest row: ends, status, date, price. The richer history card
    /// (board `3e`, «Повторить») joins with Phase 3's journal work.
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
                HStack(alignment: .top, spacing: Layout.Spacing.unit) {
                    PointBadge(role: .start)
                    Text(row.from)
                        .font(.subheadline)
                }
                HStack(alignment: .top, spacing: Layout.Spacing.unit) {
                    PointBadge(role: .end)
                    Text(row.to)
                        .font(.subheadline)
                    if let priceText = row.priceText {
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
    DeliveriesView.Content(
        isSignedIn: true,
        rows: [
            .init(
                id: UUID(),
                status: .searching,
                from: "Москва, ул Москворечье, 6",
                to: "Москва, Каширское шоссе, 52",
                dateText: "6 Sep, 11:40",
                priceText: "1 190 ₽"
            ),
            .init(
                id: UUID(),
                status: .done,
                from: "Санкт-Петербург, Невский проспект, 100",
                to: "Москва, Арбат, 10",
                dateText: "4 Sep",
                priceText: "3 400 ₽"
            ),
        ],
        compose: {}
    )
}

#Preview("Signed in, empty") {
    DeliveriesView.Content(isSignedIn: true, rows: [], compose: {})
}

#Preview("Signed out") {
    DeliveriesView.Content(isSignedIn: false, rows: [], compose: {})
}
