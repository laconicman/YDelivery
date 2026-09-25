import MapKit
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension OrderDetailView {
    /// Pure presentation: the order as remembered, and — while cancellable — the live
    /// terms of closing it. States are distinct branches, not show/hide (R9): asking,
    /// answered, refused, in flight, done.
    struct Content: View {
        let order: Order
        /// «Ваши поля» values as stored — name snapshots, in schema order.
        /// Absent means none were written, and the section stays away.
        var fields: [OrderCustomField] = []
        /// The recipient-facing share text, composed upstream — empty hides
        /// the row rather than offering a blank share (board `5d`).
        var shareText: String = ""
        let cancellation: Model.Cancellation
        /// Post-answer work is in flight — the retry stays visible but refuses a
        /// second tap, so the button says so rather than swallowing it (PR #32).
        let reconciling: Bool
        let retry: () -> Void
        let confirm: () -> Void

        @State private var showsConfirmation = false
        /// The pin↔row agreement (board `4a`): the map's pin, the callout's card,
        /// and the route row all read this one index.
        @State private var selectedStop: Int?

        var body: some View {
            List {
                Section {
                    RouteMap(
                        points: order.route,
                        etaMinutes: order.etaMinutes,
                        providerObservedAt: order.providerObservedAt,
                        selection: $selectedStop
                    )
                    .frame(height: Self.mapHeight)
                    .listRowInsets(EdgeInsets())

                    RouteLine(points: order.route, selection: $selectedStop)
                        .font(.subheadline)
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

                // The sender's own fields, as they were recorded — the snapshots
                // render even where their definition is since deleted (board `4b`).
                if !fields.isEmpty {
                    Section {
                        ForEach(fields) { field in
                            LabeledContent(field.name, value: field.value)
                        }
                    } header: {
                        Text("Your fields")
                    }
                }

                // The one way out (board `5d`): the recipient-facing text, not
                // an app link — the sheet's Copy covers "send it in chat".
                if !shareText.isEmpty {
                    Section {
                        ShareLink(item: shareText) {
                            Label("Share with the recipient",
                                  systemSymbol: .squareAndArrowUp)
                        }
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
                                Button("Try again", action: retry)
                                    .disabled(reconciling)
                            }
                        case .failed(let message), .unconfirmed(let message),
                             .unrecorded(let message):
                            Text(message)
                                .font(.footnote)
                            Button("Try again", action: retry)
                                .disabled(reconciling)
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

        /// A map section's height — enough to read the route's shape, short enough
        /// that the list beneath it never waits.
        private static let mapHeight: CGFloat = 200

    }

    /// The order's route as a map: the `2c` marks on a straight-line polyline (the
    /// wire carries no driven legs for a placed order — the drawn path is the route
    /// order, honestly). Tapping a mark opens its callout; the card floats over the
    /// map's top edge so the list below never jumps.
    struct RouteMap: View {
        let points: [RoutePoint]
        /// The provider's whole-route estimate — the end stop's card speaks it.
        let etaMinutes: Int?
        /// The provider's own as-of stamp — the card's timeline claims are this
        /// fresh, and the card says so rather than pose as live.
        let providerObservedAt: Date?
        @Binding var selection: Int?
        @State private var camera: MapCameraPosition = .automatic

        private static let routeLineWidth: CGFloat = 4
        private static let markShadowRadius: CGFloat = 1.5
        private static let markShadowDrop: CGFloat = 1
        /// A selected mark grows, anchored at its tip — the coordinate stays put.
        private static let selectedScale: CGFloat = 1.3

        /// The same `2c` mapping the route list draws — pin and row agree because
        /// they come from the one function.
        private var stops: [RouteLine.Stop] { RouteLine.stops(from: points) }

        var body: some View {
            Map(position: $camera) {
                if points.count > 1 {
                    MapPolyline(coordinates: points.map(\.coordinate))
                        .stroke(.tint, style: StrokeStyle(
                            lineWidth: Self.routeLineWidth, lineCap: .round
                        ))
                }
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    Annotation(
                        coordinate: points[index].coordinate,
                        anchor: stop.role.mapAnchor
                    ) {
                        Button {
                            selection = selection == index ? nil : index
                        } label: {
                            PointBadge(role: stop.role)
                                .shadow(
                                    radius: Self.markShadowRadius,
                                    y: Self.markShadowDrop
                                )
                                .scaleEffect(
                                    selection == index ? Self.selectedScale : 1,
                                    anchor: stop.role.mapAnchor
                                )
                        }
                        .accessibilityLabel(Text(stop.role.words))
                    } label: {
                        EmptyView()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let selection, points.indices.contains(selection) {
                    callout(for: points[selection], at: selection)
                }
            }
        }

        /// The live stop's card: the courier's account of the point first (the
        /// mini-timeline), then the door and the person. A live order has no
        /// point editor, so no card-tap navigation — its action is the call.
        private func callout(for point: RoutePoint, at index: Int) -> some View {
            PointCallout.Card(
                title: point.compactAddress,
                subtitle: subtitle(for: index),
                close: { selection = nil }
            ) {
                PointCallout.Timeline(
                    entries: VisitTimeline.entries(route: points, selected: index)
                )
                PointCallout.DoorChips(parts: point.addressParts)
                PointCallout.ContactRow(
                    summary: point.contactSummary,
                    phone: point.contactPhone
                )
                if let providerObservedAt {
                    Text("Provider data as of \(providerObservedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        /// «Drop-off · ~14 min left» — the role word every mark already speaks, and
        /// the provider's ETA where it is meaningful: on the destination still
        /// ahead. A return leg rides the route's last seat, but the ETA is the
        /// promise to the recipient — it belongs to the drop-off (YD-15).
        private func subtitle(for index: Int) -> Text {
            let role = Text(stops[index].role.words)
            guard index == points.destinationIndex,
                  let etaMinutes,
                  points[index].visit?.status == .pending || points[index].visit?.status == .arrived
            else { return role }
            return role + Text(" · ~\(etaMinutes) min left")
        }
    }
}

nonisolated extension RoutePoint {
    /// MapKit stays at the view edge — the model keeps plain doubles.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
            reconciling: false,
            retry: {},
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
            reconciling: false,
            retry: {},
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
            reconciling: false,
            retry: {},
            confirm: {}
        )
    }
}

#Preview("Cancellable — too late") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewSearching,
            cancellation: .ready(.init(status: .other("pickuped"), version: 9, terms: .unavailable)),
            reconciling: false,
            retry: {},
            confirm: {}
        )
    }
}

#Preview("Accepted — the check failed") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewSearching,
            cancellation: .unconfirmed(
                CancellationUnconfirmed(status: nil).errorDescription ?? ""
            ),
            reconciling: false,
            retry: {},
            confirm: {}
        )
    }
}

#Preview("Done — no cancel offered") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewDone,
            cancellation: .loading,
            reconciling: false,
            retry: {},
            confirm: {}
        )
    }
}

#Preview("En route — courier mid-run") {
    NavigationStack {
        OrderDetailView.Content(
            order: .previewEnRoute,
            shareText: RecipientShareText.text(
                for: .previewEnRoute, orderNumber: "4417"),
            cancellation: .ready(.init(status: .other("pickuped"), version: 9, terms: .unavailable)),
            reconciling: false,
            retry: {},
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

    /// A courier mid-route: the pickup visited, the destination waiting on its
    /// estimate — the callout's mini-timeline has something to say.
    static var previewEnRoute: Order {
        Order(
            created: .init(timeIntervalSince1970: 1_800_000_000),
            status: .active,
            route: [
                RoutePoint(
                    latitude: 55.646068, longitude: 37.668176,
                    address: "Москва, ул Москворечье, 6",
                    contactName: "Иван Петров",
                    visit: .init(
                        status: .visited,
                        visitedAt: .init(timeIntervalSince1970: 1_800_001_200)
                    )
                ),
                RoutePoint(
                    latitude: 55.652212, longitude: 37.648210,
                    address: "Москва, Каширское шоссе, 52",
                    addressParts: .init(entrance: "2", apartment: "15"),
                    contactName: "Анна Сидорова",
                    contactPhone: "+79987654321",
                    visit: .init(
                        status: .pending,
                        expectedAt: .init(timeIntervalSince1970: 1_800_002_400)
                    )
                ),
            ],
            price: "1767.78",
            currency: "RUB",
            tariff: "express",
            claimID: "claim-preview-live",
            courierName: "Сергей",
            etaMinutes: 14,
            providerStatus: "pickuped"
        )
    }
}
#endif
