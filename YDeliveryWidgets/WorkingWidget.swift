import SFSafeSymbols
import SwiftUI
import WidgetKit
import YDeliveryKit

/// The working widget (board `5b`): repeat a saved route, so tomorrow's
/// warehouse run starts from the Home Screen. Each row is a recent route —
/// the first and last stops are all a repeat needs — and a tap opens a
/// pre-filled draft through the app's deep link. «Новая» is the door to a
/// blank one. Nothing here orders: the widget's affordance is *open*, and
/// the price the sender reviews waits inside.
struct WorkingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Working", provider: Provider()) { entry in
            WorkingView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Repeat a delivery")
        .description("Yesterday's routes, one tap from a new draft.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }

    struct Entry: TimelineEntry {
        let date: Date
        /// Recent routes as repeat candidates — newest first, already
        /// deduplicated by destination so «Дом → ПВЗ» doesn't repeat twice.
        let routes: [DeliverySnapshot.Entry]
    }

    struct Provider: TimelineProvider {
        /// How many routes a medium can hold — small takes the first two.
        private static let routeLimit = 4

        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, routes: [.sampleRoute, .sampleRouteSecond])
        }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(load())
        }
        func getTimeline(in context: Context,
                         completion: @escaping (Timeline<Entry>) -> Void) {
            // Recents change only when the app writes — the half-hour floor
            // merely covers long quiet stretches.
            completion(Timeline(entries: [load()],
                                policy: .after(.now.addingTimeInterval(30 * 60))))
        }
        private func load() -> Entry {
            var seen = Set<String>()
            let routes = (WidgetStore.load()?.orders ?? []).filter { order in
                // A repeat needs both ends — a one-stop note has no route.
                guard let key = order.destinationKey,
                      order.pickupAddress != nil,
                      order.pickupAddress != order.destinationAddress
                else { return false }
                return seen.insert(key).inserted
            }
            return Entry(date: .now, routes: Array(routes.prefix(Self.routeLimit)))
        }
    }
}

private struct WorkingView: View {
    let entry: WorkingWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var routeLimit: Int { family == .systemSmall ? 2 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
            Label("Repeat", systemSymbol: .repeat)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(entry.routes.prefix(routeLimit)) { order in
                routeRow(order)
            }
            Spacer(minLength: 0)
            if family == .systemMedium {
                newRow
            }
        }
        .widgetURL(WidgetLink.compose)
    }

    /// «Склад → Арбат» — compact addresses, one line, a tap opens the draft.
    private func routeRow(_ order: DeliverySnapshot.Entry) -> some View {
        Link(destination: WidgetLink.repeatOrder(order.id)) {
            HStack(spacing: Layout.Spacing.chip) {
                Image(systemSymbol: .arrowRightCircle)
                    .foregroundStyle(.secondary)
                Text("\(order.pickupAddress ?? "") → \(order.destinationAddress ?? "")")
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var newRow: some View {
        Link(destination: WidgetLink.compose) {
            Label("New delivery", systemSymbol: .plusCircleFill)
                .font(.caption.weight(.medium))
        }
    }
}

private extension DeliverySnapshot.Entry {
    static var sampleRoute: Self {
        DeliverySnapshot.Entry(
            id: UUID(), status: .done, isLive: false,
            pickupAddress: "Склад на Невском, 1",
            destinationAddress: "Арбат, 12",
            destinationKey: "sample-1")
    }
    static var sampleRouteSecond: Self {
        DeliverySnapshot.Entry(
            id: UUID(), status: .done, isLive: false,
            pickupAddress: "Москворечье, 6",
            destinationAddress: "ПВЗ Север, 4",
            destinationKey: "sample-2")
    }
}

#if DEBUG
struct WorkingWidget_Previews: PreviewProvider {
    static var previews: some View {
        let entry = WorkingWidget.Entry(
            date: .now, routes: [.sampleRoute, .sampleRouteSecond])
        Group {
            WorkingView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            WorkingView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
#endif
