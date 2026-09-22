import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension OrderDetailView {
    /// Pure presentation: the order as remembered, and — while cancellable — the live
    /// terms of closing it. States are distinct branches, not show/hide (R9): asking,
    /// answered, refused, in flight, done.
    struct Content: View {
        let order: Order
        let cancellation: Model.Cancellation
        let reload: () -> Void
        let confirm: () -> Void

        @State private var showsConfirmation = false

        var body: some View {
            List {
                Section {
                    ForEach(Array(order.route.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: Layout.Spacing.unit) {
                            PointBadge(role: badgeRole(at: index))
                            VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                                Text(point.address)
                                    .font(.subheadline)
                                if let name = point.contactName, !name.isEmpty {
                                    Text(name)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        StatusChip(status: order.status)
                        Spacer()
                        Text(order.created.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let priceText = order.priceText {
                        LabeledContent("Price", value: priceText)
                    }
                    if let tariff = order.tariff {
                        LabeledContent("Tariff", value: tariff)
                    }
                }

                if order.isCancellable {
                    Section {
                        switch cancellation {
                        case .loading:
                            HStack(spacing: Layout.Spacing.unit) {
                                ProgressView()
                                Text("Asking what cancelling costs…")
                                    .foregroundStyle(.secondary)
                            }
                        case .ready(let current):
                            Text(current.terms.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if current.terms.isConfirmable {
                                Button(current.terms.buttonTitle, role: .destructive) {
                                    showsConfirmation = true
                                }
                            } else if current.terms != .unavailable {
                                // Paid, but the amount never arrived — consenting
                                // to an unseen charge is not offered (PR #32).
                                Button("Try again", action: reload)
                            }
                        case .failed(let message):
                            Text(message)
                                .font(.footnote)
                            Button("Try again", action: reload)
                        case .cancelling:
                            HStack(spacing: Layout.Spacing.unit) {
                                ProgressView()
                                Text("Cancelling…")
                                    .foregroundStyle(.secondary)
                            }
                        case .cancelled:
                            Label("Cancelled", systemSymbol: .checkmarkCircleFill)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Cancellation")
                    }
                }
            }
            .confirmationDialog(
                "Cancel this delivery?",
                isPresented: $showsConfirmation,
                titleVisibility: .visible
            ) {
                if case .ready(let current) = cancellation, current.terms.isConfirmable {
                    Button(current.terms.buttonTitle, role: .destructive, action: confirm)
                    Button("Keep the order", role: .cancel) {}
                }
            }
        }

        /// First stop wears the ring, last the teardrop, middles their position number —
        /// the same `2c` mapping the draft rows use.
        private func badgeRole(at index: Int) -> PointBadge.Role {
            if index == 0 { return .start }
            if index == order.route.count - 1 { return .end }
            return .stop(number: index + 1)
        }
    }
}

nonisolated extension Order {
    /// The price formatted for display, parsed back from the wire's POSIX decimal
    /// string — the one read of stored money, shared by the list row and the detail.
    var priceText: String? {
        price.flatMap { price in
            Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")).map {
                $0.formatted(.currency(code: currency ?? "RUB").precision(.fractionLength(0...2)))
            }
        }
    }
}

#Preview("Cancellable — free terms") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewSearching,
            cancellation: .ready(.init(status: .searching, version: 4, terms: .free)),
            reload: {},
            confirm: {}
        )
    }
}

#Preview("Cancellable — paid terms") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewSearching,
            cancellation: .ready(.init(
                status: .other("performer_found"), version: 4,
                terms: .paid(price: 807.6, currency: "RUB")
            )),
            reload: {},
            confirm: {}
        )
    }
}

#Preview("Cancellable — paid, price never arrived") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewSearching,
            cancellation: .ready(.init(
                status: .other("performer_found"), version: 4,
                terms: .paid(price: nil, currency: nil)
            )),
            reload: {},
            confirm: {}
        )
    }
}

#Preview("Cancellable — too late") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewSearching,
            cancellation: .ready(.init(status: .other("pickuped"), version: 9, terms: .unavailable)),
            reload: {},
            confirm: {}
        )
    }
}

#Preview("Done — no cancel offered") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewDone,
            cancellation: .loading,
            reload: {},
            confirm: {}
        )
    }
}

#if DEBUG
extension Order {
    /// Preview fixtures — a claim still being worked, and one long done.
    static var previewSearching: Order {
        Order(
            created: .init(timeIntervalSince1970: 1_800_000_000),
            status: .searching,
            route: [
                RoutePoint(latitude: 55.646068, longitude: 37.668176, address: "Москва, ул Москворечье, 6", contactName: "Иван Петров"),
                RoutePoint(latitude: 55.652212, longitude: 37.648210, address: "Москва, Каширское шоссе, 52", contactName: "Анна"),
            ],
            price: "1767.78",
            currency: "RUB",
            tariff: "express",
            claimID: "claim-preview-1"
        )
    }

    static var previewDone: Order {
        Order(
            created: .init(timeIntervalSince1970: 1_700_000_000),
            status: .done,
            route: [
                RoutePoint(latitude: 55.75, longitude: 37.6, address: "Москва, Тверская, 1"),
                RoutePoint(latitude: 55.76, longitude: 37.62, address: "Москва, Арбат, 10"),
            ],
            price: "3400",
            currency: "RUB",
            tariff: "courier",
            claimID: "claim-preview-2"
        )
    }
}
#endif
