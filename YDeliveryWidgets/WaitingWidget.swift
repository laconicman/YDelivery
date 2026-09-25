import SFSafeSymbols
import SwiftUI
import WidgetKit
import YDeliveryKit

/// The waiting widget (board `5b`): the active delivery on the Home Screen —
/// «where is it» answered without a tap. One order takes the headline — the
/// most recently moved live one — and the medium size lists the rest of the
/// board («ещё в работе») so two deliveries never compete for the card.
///
/// The board's one rule holds for every size: no price as the only content,
/// nothing irreversible — the widget opens the order, it never acts on it.
/// And empty is not «Нет заказов»: with nothing live the surface offers the
/// repeat shortcut instead of a void.
struct WaitingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Waiting", provider: Provider()) { entry in
            WaitingView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Delivery")
        .description("Where the active delivery is, without opening the app.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular,
        ])
        .contentMarginsDisabled()
    }

    struct Entry: TimelineEntry {
        let date: Date
        /// The headline order — nil when nothing is live.
        let order: DeliverySnapshot.Entry?
        /// The rest of the live set, newest first — the medium's «ещё в работе».
        let alsoLive: [DeliverySnapshot.Entry]
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, order: .sample, alsoLive: [.sampleSecondary])
        }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(load())
        }
        func getTimeline(in context: Context,
                         completion: @escaping (Timeline<Entry>) -> Void) {
            // The app reloads timelines on every republish; this is only the
            // floor — a half-hourly re-read keeps a long-stale card honest
            // even while the app sleeps.
            completion(Timeline(entries: [load()],
                                policy: .after(.now.addingTimeInterval(30 * 60))))
        }
        private func load() -> Entry {
            let live = (WidgetStore.load()?.orders ?? []).filter(\.isLive)
            return Entry(date: .now, order: live.first,
                         alsoLive: Array(live.dropFirst()))
        }
    }
}

/// The widget's surfaces, one view family-switched — the size axis picks how
/// much of the card shows, never a different truth.
private struct WaitingView: View {
    let entry: WaitingWidget.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Lock screen

    /// «🛵 14м» — glyph and the wait, nothing else fits the circle.
    private var circular: some View {
        VStack(spacing: Layout.Spacing.hairline) {
            if let symbol = entry.order?.status.symbol {
                Image(systemSymbol: symbol)
            } else {
                Image(systemSymbol: .shippingbox)
            }
            if let order = entry.order {
                ETALabel(at: order.etaAt, observedAt: order.providerObservedAt,
                         presentation: .duration)
                    .font(.caption2)
            }
        }
        .widgetURL(entry.order.map { WidgetLink.order($0.id) } ?? WidgetLink.compose)
    }

    /// «🛵 №4417 · 9:41 / Едет к получателю» — status and ETA, no graphics.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
            if let order = entry.order {
                HStack(spacing: Layout.Spacing.tight) {
                    OrderIdentity(number: order.orderNumber, size: .compact)
                    ETALabel(at: order.etaAt, presentation: .clock)
                }
                .font(.caption.weight(.semibold))
                Text(verbatim: WidgetPhrases.statusLine(order))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("New delivery")
                    .font(.caption)
            }
        }
        .widgetURL(entry.order.map { WidgetLink.order($0.id) } ?? WidgetLink.compose)
    }

    // MARK: Home Screen

    /// «🛵 №4417 / 9:41 / Едет к получателю» — the irreducible card.
    private var small: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
            if let order = entry.order {
                HStack(spacing: Layout.Spacing.chip) {
                    if let symbol = order.status.symbol {
                        Image(systemSymbol: symbol)
                            .foregroundStyle(order.status.color)
                    }
                    OrderIdentity(number: order.orderNumber, size: .compact)
                }
                .font(.subheadline.weight(.semibold))
                ETALabel(at: order.etaAt, presentation: .clock)
                    .font(.title2.weight(.bold))
                Text(verbatim: WidgetPhrases.statusLine(order))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                emptySurface
            }
        }
        .widgetURL(entry.order.map { WidgetLink.order($0.id) } ?? WidgetLink.compose)
    }

    /// The full card: headline + ETA pair, route ends, courier, and the rest
    /// of the board — «ещё в работе» and the repeat door to «Новая».
    private var medium: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
            if let order = entry.order {
                HStack(alignment: .firstTextBaseline) {
                    StatusChip(status: order.status)
                    OrderIdentity(number: order.orderNumber)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    ETALabel(at: order.etaAt, presentation: .clock)
                        .font(.headline)
                    ETALabel(at: order.etaAt, observedAt: order.providerObservedAt,
                             presentation: .duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let pickup = order.pickupAddress,
                   let destination = order.destinationAddress {
                    Text("\(pickup) → \(destination)")
                        .font(.caption)
                        .lineLimit(1)
                }
                if order.courierName != nil || order.courierVehicle != nil {
                    Text([order.courierName, order.courierVehicle]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                alsoLiveStrip
            } else {
                emptySurface
            }
        }
        .widgetURL(entry.order.map { WidgetLink.order($0.id) } ?? WidgetLink.compose)
    }

    /// «Ещё в работе №4418 ищем · №4416 вручено» — the medium's bottom strip;
    /// a tap opens that order, «Новая» opens a fresh draft.
    @ViewBuilder
    private var alsoLiveStrip: some View {
        HStack(spacing: Layout.Spacing.unit) {
            if !entry.alsoLive.isEmpty {
                Text("Also live")
                    .foregroundStyle(.secondary)
                ForEach(entry.alsoLive) { item in
                    Link(destination: WidgetLink.order(item.id)) {
                        (Text("№\(item.orderNumber ?? "—") ")
                            + Text(item.status.words))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Link(destination: WidgetLink.compose) {
                Label("New", systemSymbol: .plusCircle)
            }
        }
        .font(.caption2)
    }

    /// No live delivery — the board says offer the repeat door, not a void.
    private var emptySurface: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
            Image(systemSymbol: .shippingbox)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Nothing on the way")
                .font(.subheadline.weight(.semibold))
            Text("Start a new delivery")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The wire word as the widget's one-line status — the Kit's phrase table with
/// the collapsed status as the fallback.
enum WidgetPhrases {
    static func statusLine(_ order: DeliverySnapshot.Entry) -> String {
        if let word = order.providerStatus,
           let phrase = ProviderStatusPhrase.phrase(for: word) {
            return String(localized: phrase)
        }
        return String(localized: order.status.words)
    }
}

private extension DeliverySnapshot.Entry {
    /// Preview data — a courier mid-route, in the wire's own words.
    static var sample: Self {
        DeliverySnapshot.Entry(
            id: UUID(), status: .active, isLive: true, orderNumber: "4417",
            pickupAddress: "Москворечье, 6",
            destinationAddress: "Каширское шоссе, 52",
            courierName: "Сергей", courierVehicle: "м 234 ор 77",
            providerStatus: "delivery_arrived",
            etaAt: .now.addingTimeInterval(14 * 60), providerObservedAt: .now)
    }

    static var sampleSecondary: Self {
        DeliverySnapshot.Entry(
            id: UUID(), status: .searching, isLive: true, orderNumber: "4418",
            providerStatus: "performer_lookup", providerObservedAt: .now)
    }
}

#if DEBUG
struct WaitingWidget_Previews: PreviewProvider {
    static var previews: some View {
        let entry = WaitingWidget.Entry(
            date: .now, order: .sample, alsoLive: [.sampleSecondary])
        Group {
            WaitingView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            WaitingView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            WaitingView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
            WaitingView(entry: .init(date: .now, order: nil, alsoLive: []))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
#endif
