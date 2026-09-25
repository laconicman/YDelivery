import MapKit
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

/// The pin's card (board `4a`): what the row cannot carry — the door, the person,
/// and on a live order the courier's own account of the stop. One chrome for the
/// draft and the order detail; what differs rides the content slot. A callout is
/// never the only route to anything — every field and action it shows is also on
/// the route's rows (the rule the board sets in words).
enum PointCallout {
    /// A floating card's lift — kept small: the map beneath must stay legible.
    static let shadowRadius: CGFloat = 8
    static let shadowDrop: CGFloat = 2

    /// The floating card: title is the stop's own address, subtitle its role in
    /// this route, `close` the ✕ that must always be there. `open` is the board's
    /// card-tap → editor rule — `nil` where nothing answers (a live order has no
    /// point editor; its actions are buttons inside).
    struct Card<Content: View>: View {
        let title: String
        let subtitle: Text
        let close: () -> Void
        var open: (() -> Void)? = nil
        @ViewBuilder var content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.unit) {
                HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
                    VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        subtitle
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: close) {
                        Image(systemSymbol: .xmark)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Close"))
                }
                content()
            }
            .padding(Layout.Spacing.gutter)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: Layout.Radius.card)
            )
            .shadow(radius: PointCallout.shadowRadius, y: PointCallout.shadowDrop)
            .padding(.horizontal, Layout.Spacing.edge)
            .contentShape(RoundedRectangle(cornerRadius: Layout.Radius.card))
            .onTapGesture { open?() }
            // The card reads as a button only when tapping it goes somewhere.
            .accessibilityAddTraits(open == nil ? [] : .isButton)
        }
    }

    /// The door facts as chips — building, entrance, floor, flat, intercom (board
    /// `4a`'s «всегда» line). Absent parts simply don't draw; a point with none shows
    /// nothing rather than a row of empties. `building` leads — it qualifies the
    /// address itself before the way in.
    struct DoorChips: View {
        let parts: AddressParts?

        var body: some View {
            if let parts, !parts.isEmpty {
                ChipFlow(spacing: Layout.Spacing.unit) {
                    if !parts.building.isEmpty {
                        chip { Text("Bldg. \(parts.building)") }
                    }
                    if !parts.entrance.isEmpty {
                        chip { Text("Entrance \(parts.entrance)") }
                    }
                    if !parts.floor.isEmpty {
                        chip { Text("Floor \(parts.floor)") }
                    }
                    if !parts.apartment.isEmpty {
                        chip { Text("Flat \(parts.apartment)") }
                    }
                    if !parts.intercom.isEmpty {
                        chip { Text("Intercom \(parts.intercom)") }
                    }
                }
            }
        }

        private func chip(_ label: () -> Text) -> some View {
            label()
                .font(.footnote)
                .padding(.horizontal, Layout.Spacing.unit)
                .padding(.vertical, Layout.Spacing.tight)
                .background(
                    Color(.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: Layout.Radius.field)
                )
        }
    }

    /// Who stands at the door — the summary line and, when a phone is aboard, the
    /// call affordance. The `tel:` URL is built from digits alone so a stored
    /// pretty-printed number still dials; no phone means no button, not a dead one.
    struct ContactRow: View {
        let summary: String?
        /// The dialable number — display stays `summary`'s job.
        let phone: String?

        var body: some View {
            if let summary, !summary.isEmpty {
                HStack(spacing: Layout.Spacing.unit) {
                    Text(summary)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let url = Self.callURL(phone) {
                        Link(destination: url) {
                            Image(systemSymbol: .phoneFill)
                                .font(.footnote.weight(.semibold))
                        }
                        .accessibilityLabel(Text("Call"))
                    }
                }
            }
        }

        /// `tel:` takes digits and a leading `+` — anything else is formatting the
        /// scheme would choke on.
        static func callURL(_ phone: String?) -> URL? {
            guard let phone else { return nil }
            let digits = phone.filter(\.isNumber)
            guard !digits.isEmpty else { return nil }
            return URL(string: "tel:\(phone.hasPrefix("+") ? "+" : "")\(digits)")
        }
    }

    /// What moves at this stop — the draft callout's parcel line (board `4a`'s
    /// «что здесь происходит с посылками»). The counted sentence is the callout
    /// seat of `7d`'s `PointParcelActions`; the grouped item list lands with the
    /// row's disclosure then, and this line is replaced by that component when it
    /// ships (decision 49 keeps the two surfaces on one vocabulary).
    struct ParcelRow: View {
        let leaving: Int
        let arriving: Int

        var body: some View {
            if leaving + arriving > 0 {
                HStack(spacing: Layout.Spacing.unit) {
                    Image(systemSymbol: .shippingbox)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    sentence
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        /// «2 items leave here · 1 item arrives here» — pieces inflected, the
        /// verbs fixed (the sender's side: parcels leave and arrive).
        private var sentence: Text {
            switch (leaving > 0, arriving > 0) {
            case (true, true):
                Text("^[\(leaving) item](inflect: true) leave here · ^[\(arriving) item](inflect: true) arrive here")
            case (true, false):
                Text("^[\(leaving) item](inflect: true) leave here")
            default:
                Text("^[\(arriving) item](inflect: true) arrive here")
            }
        }
    }

    /// The live order's per-stop progress (board `4a`'s «только в живом заказе»):
    /// what already happened upstream, what is happening here, what the provider
    /// still expects. Rows are `VisitTimeline` entries — derivation lives there.
    struct Timeline: View {
        let entries: [VisitTimeline.Entry]

        var body: some View {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        row(entry)
                    }
                }
            }
        }

        private func row(_ entry: VisitTimeline.Entry) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: Layout.Spacing.unit) {
                mark(for: entry.mark)
                (entry.fact.words + (entry.time.map {
                    Text(" · \($0.formatted(date: .omitted, time: .shortened))")
                } ?? Text("")))
                    .font(.footnote)
                    .foregroundStyle(entry.mark == .next ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        @ViewBuilder private func mark(for mark: VisitTimeline.Entry.Mark) -> some View {
            switch mark {
            case .past:
                Image(systemSymbol: .checkmarkCircleFill)
                    .foregroundStyle(.secondary)
            case .current:
                Image(systemSymbol: .smallcircleFilledCircleFill)
                    .foregroundStyle(Color.accentColor)
            case .next:
                Image(systemSymbol: .circle)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension VisitTimeline.Entry.Fact {
    /// The row's words — one home so the card, and VoiceOver over the card, agree.
    var words: Text {
        switch self {
        case .priorVisit(let pickup, let address):
            pickup ? Text("Picked up at \(address)") : Text("Handed over at \(address)")
        case .visitedHere(let pickup):
            pickup ? Text("Picked up here") : Text("Handed over here")
        case .arrived:
            Text("Courier is at the door")
        case .enRoute:
            Text("Heading here now")
        case .pending:
            Text("Not visited yet")
        case .skipped:
            Text("Skipped by the courier")
        case .expected:
            Text("Expected")
        }
    }
}

/// A row that wraps — the door chips' layout. Left to right, a new line when the
/// row fills: `Layout` since iOS 16, small because the contract is small. The
/// protocol spells its module because the Kit's `Layout` token enum holds the name.
private struct ChipFlow: SwiftUI.Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let frames = arranged(in: proposal.width ?? .infinity, subviews: subviews)
        return frames.reduce(.zero) { size, frame in
            CGSize(width: max(size.width, frame.maxX), height: max(size.height, frame.maxY))
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        for (frame, subview) in zip(arranged(in: bounds.width, subviews: subviews), subviews) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arranged(in width: CGFloat, subviews: LayoutSubviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

#Preview("Draft point — door and person") {
    VStack {
        PointCallout.Card(
            title: "ул. Москворечье, 6",
            subtitle: Text("Pick up · first stop"),
            close: {},
            open: {}
        ) {
            PointCallout.DoorChips(parts: AddressParts(
                entrance: "А", floor: "3", apartment: "301", intercom: "301К"
            ))
            PointCallout.ContactRow(
                summary: "Иван Петров · +7 912 345-67-89",
                phone: "+79123456789"
            )
            PointCallout.ParcelRow(leaving: 2, arriving: 0)
        }
        Spacer()
    }
    .padding(.top)
    .background(Map(position: .constant(.automatic)).opacity(0.3))
}

#Preview("Live stop — the courier's account") {
    let visitedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let expectedAt = Date(timeIntervalSince1970: 1_800_002_400)
    let route = [
        RoutePoint(latitude: 55.646, longitude: 37.668, address: "Москва, ул Москворечье, 6",
                   visit: .init(status: .visited, visitedAt: visitedAt)),
        RoutePoint(latitude: 55.652, longitude: 37.648, address: "Москва, Каширское шоссе, 52",
                   visit: .init(status: .pending, expectedAt: expectedAt)),
    ]
    VStack {
        PointCallout.Card(
            title: "Каширское шоссе, 52",
            subtitle: Text("Drop-off · ~14 min left"),
            close: {}
        ) {
            PointCallout.Timeline(
                entries: VisitTimeline.entries(route: route, selected: 1)
            )
            PointCallout.DoorChips(parts: AddressParts(entrance: "2", apartment: "15"))
            PointCallout.ContactRow(
                summary: "Анна Сидорова · +7 998 765-43-21",
                phone: "+79987654321"
            )
        }
        Spacer()
    }
    .padding(.top)
    .background(Map(position: .constant(.automatic)).opacity(0.3))
}
