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
            LockScreenView(state: context.state, isStale: context.isStale)
                .widgetURL(WidgetLink.order(context.attributes.orderID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    statusGlyph(context.state.status)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Stale, the stamp below qualifies this figure — «~14 мин»
                    // as of 9:27, the Lock Screen's own pairing. Only compact,
                    // with no room for a stamp, trades it for the clock.
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
                    VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                        HStack {
                            OrderIdentity(number: context.state.orderNumber, size: .compact)
                            Text(verbatim: "·")
                            Text(context.state.destinationAddress)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            callButton(phone: context.state.destinationPhone)
                        }
                        .font(.caption2)
                        // Board `5a` gives the island no as-of line; a stale
                        // card earns one — the Lock Screen's own words
                        // (review, PR #134).
                        if context.isStale {
                            ActivityStamp(observedAt: context.state.providerObservedAt,
                                          isStale: true)
                        }
                    }
                }
            } compactLeading: {
                statusGlyph(context.state.status)
            } compactTrailing: {
                // Stale, the frozen «~14 мин» would read as a wait from now;
                // the clock form stays true however old the reading is.
                ETALabel(at: context.state.etaAt,
                         observedAt: context.state.providerObservedAt,
                         presentation: context.isStale ? .clock : .duration)
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
/// «as of 9:27» is what keeps a dead activity from posing as live — and once
/// the card passes its stale date (`LiveActivityController.staleAfter` since
/// the app last checked) the stamp says so outright: «not updating · as of 9:27».
private struct LockScreenView: View {
    let state: DeliveryActivityAttributes.ContentState
    let isStale: Bool

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
            ActivityStamp(observedAt: state.providerObservedAt, isStale: isStale)
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

/// The as-of line, or its stale form — the one place a card admits the app
/// has not been able to refresh it. The Lock Screen always carries it; the
/// expanded island only once the card is stale.
private struct ActivityStamp: View {
    let observedAt: Date?
    let isStale: Bool

    var body: some View {
        if isStale {
            Group {
                if let observedAt {
                    Text("Not updating · as of \(Text(observedAt, style: .time))")
                } else {
                    Text("Not updating")
                }
            }
            .font(.caption2.weight(.medium))
        } else if let observedAt {
            (Text("as of ")
                + Text(observedAt, style: .time))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
private extension DeliveryActivityAttributes.ContentState {
    /// The card at its fullest — courier assigned, ETA known, recipient
    /// reachable — the state a preview must prove fits.
    static var previewEnRoute: Self {
        DeliveryActivityAttributes.ContentState(
            status: .active, orderNumber: "4417",
            destinationAddress: "Каширское шоссе, 52",
            courierName: "Сергей", courierVehicle: "м 234 ор 77",
            providerStatus: "delivery_arrived",
            etaAt: .now.addingTimeInterval(14 * 60),
            providerObservedAt: .now,
            destinationPhone: "+7 (812) 345-67-89")
    }
}

#Preview("Lock screen") {
    LockScreenView(state: .previewEnRoute, isStale: false)
        .padding(.vertical)
}

#Preview("Lock screen, stale") {
    LockScreenView(state: .previewEnRoute, isStale: true)
        .padding(.vertical)
}

#Preview("Stamp — live, stale, stale with no stamp") {
    VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
        ActivityStamp(observedAt: .now, isStale: false)
        ActivityStamp(observedAt: .now, isStale: true)
        ActivityStamp(observedAt: nil, isStale: true)
    }
    .padding()
}
#endif
