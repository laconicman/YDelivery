import ActivityKit
import SFSafeSymbols
import SwiftUI
import WidgetKit
import YDeliveryKit

/// The Live Activity (board `5a`): «one glance, one action». Content priority
/// is the board's own order — where it is now, when it gets there, who to call
/// if something's wrong — and the identifier shown is the sender's own number,
/// never the vendor's claim id. The dashed route remainder is the only graphic
/// the board allows; a live map is a battery bill for what the ETA already says.
///
/// Everything renders from `ContentState` — the app's `LiveActivityController`
/// writes provider truth here on every sync pass, and `providerObservedAt` is
/// the staleness stamp the card must show so a dead activity never looks live.
struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .widgetURL(WidgetLink.order(context.attributes.orderID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    statusGlyph(context.state.status)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ETALabel(at: context.state.etaAt,
                             observedAt: context.state.providerObservedAt,
                             presentation: .duration)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(statePhrase(context.state))
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        OrderIdentity(number: context.state.orderNumber, size: .compact)
                        Text(verbatim: "·")
                        Text(context.state.destinationAddress)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        callButton(phone: context.state.destinationPhone)
                    }
                    .font(.caption2)
                }
            } compactLeading: {
                statusGlyph(context.state.status)
            } compactTrailing: {
                ETALabel(at: context.state.etaAt,
                         observedAt: context.state.providerObservedAt,
                         presentation: .duration)
                    .font(.caption2.weight(.semibold))
            } minimal: {
                statusGlyph(context.state.status)
            }
        }
    }

    /// The status glyph — the island's irreducible form.
    @ViewBuilder
    private func statusGlyph(_ status: OrderStatus) -> some View {
        if let symbol = status.symbol {
            Image(systemSymbol: symbol)
                .foregroundStyle(status.color)
        } else {
            Image(systemSymbol: .shippingbox)
        }
    }

    /// «Получателю» — the one call the wire can support: the courier's number
    /// is never sent (`performer_info` carries name and vehicle only), so the
    /// board's «Курьеру» button has nothing to dial and stays undrawn.
    @ViewBuilder
    private func callButton(phone: String?) -> some View {
        if let phone, let url = Self.telURL(phone) {
            Link(destination: url) {
                Label("Recipient", systemSymbol: .phoneFill)
            }
        }
    }

    /// `tel:` takes digits and a leading `+` — punctuation the contact fields
    /// allow («(812) 345-67-89 доб. 12») must never reach the URL.
    static func telURL(_ phone: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(phone.hasPrefix("+") ? "+" : "")\(digits)")
    }

    /// The headline — the wire word's phrase, falling back to the collapsed
    /// status's words when the provider has said nothing the table knows.
    private func statePhrase(_ state: DeliveryActivityAttributes.ContentState) -> String {
        if let word = state.providerStatus,
           let phrase = ProviderStatusPhrase.phrase(for: word) {
            return String(localized: phrase)
        }
        return String(localized: state.status.words)
    }
}

/// The Lock Screen card, board `5a` verbatim: order number and destination on
/// top, the wire's own phrase as the headline, the courier line, then the two
/// ETA readings — the clock («9:41») the sender plans against and the duration
/// («~14 мин») the wait feels like. The staleness stamp rides at the bottom:
/// «as of 9:27» is what keeps a dead activity from posing as live.
private struct LockScreenView: View {
    let state: DeliveryActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                OrderIdentity(number: state.orderNumber)
                    .font(.headline)
                Spacer(minLength: 0)
                Text(state.destinationAddress)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Text(headline)
                .font(.subheadline.weight(.medium))
            if state.courierName != nil || state.courierVehicle != nil {
                Text([state.courierName, state.courierVehicle]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                ETALabel(at: state.etaAt, presentation: .clock)
                    .font(.title3.weight(.bold))
                ETALabel(at: state.etaAt, observedAt: state.providerObservedAt,
                         presentation: .duration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let phone = state.destinationPhone,
                   let url = DeliveryLiveActivity.telURL(phone) {
                    Link(destination: url) {
                        Label("Recipient", systemSymbol: .phoneFill)
                            .font(.caption.weight(.medium))
                    }
                }
            }
            if let observed = state.providerObservedAt {
                (Text("as of ")
                    + Text(observed, style: .time))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Layout.Spacing.edge)
    }

    private var headline: String {
        if let word = state.providerStatus,
           let phrase = ProviderStatusPhrase.phrase(for: word) {
            return String(localized: phrase)
        }
        return String(localized: state.status.words)
    }
}
