import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension NewDeliveryView {
    /// The beginner explainer (board `3a`): a vertical list — the shape that survives
    /// accessibility sizes, which is why the paged cards lost (decision #3). It opens
    /// itself until the first order exists, then lives behind the ⓘ. Bounds are stated
    /// on every card; prices join when the strip has them.
    ///
    /// Static copy v1 (author, 2026-08-30): limits become live per-city data when the
    /// package grows the `tariffs` operation — recorded in its Roadmap.
    struct TariffExplainer: View {
        /// One class, reduced to its card.
        struct Card: Identifiable {
            let name: String
            let emoji: String
            let explanation: String?
            let limits: [String]
            let priceText: String?
            /// What in this parcel this class cannot take, when anything doesn't fit.
            /// The strip warns per item; here the sender learns *which class* the box
            /// rules out, which is the vocabulary the explainer exists to teach.
            var misfit: String? = nil

            var id: String { name }
        }

        let cards: [Card]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        ForEach(cards) { card in
                            CardRow(card: card)
                        }
                    } header: {
                        Text("Pick by the parcel's weight and size.")
                            .textCase(nil)
                    } footer: {
                        Text("A thermal bag is a courier-only option; loaders ride only in the cargo van.")
                    }
                }
                .navigationTitle("How to deliver")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

extension NewDeliveryView.TariffExplainer {
    struct CardRow: View {
        let card: Card

        var body: some View {
            HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
                Text(card.emoji)
                    .font(.title)
                VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
                    Text(card.name)
                        .font(.headline)
                    if let explanation = card.explanation {
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(card.limits, id: \.self) { limit in
                        Text(limit)
                            .font(.footnote)
                    }
                    if let misfit = card.misfit {
                        Label(misfit, systemSymbol: .exclamationmarkTriangle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let priceText = card.priceText {
                    Text(priceText)
                        .font(.headline)
                }
            }
            .padding(.vertical, Layout.Spacing.hairline)
        }
    }
}

extension NewDeliveryView.TariffExplainer.Card {
    /// A class and, when the strip already has one, its price.
    init(
        tariff: TariffClass,
        offer: Offer?,
        misfits: [ParcelItem] = [],
        parcelIsTooHeavy: Bool = false
    ) {
        let misfit: String? = if !misfits.isEmpty {
            Self.misfitWords(misfits)
        } else if parcelIsTooHeavy {
            // Every box passes on its own; together they are over the limit. Naming a
            // box here would blame the wrong thing.
            String(localized: "Everything fits, but together it's too heavy for this class")
        } else {
            nil
        }
        self.init(
            name: tariff.words,
            emoji: tariff.emoji,
            explanation: tariff.explanation,
            limits: tariff.limits,
            priceText: offer?.priceText,
            misfit: misfit
        )
    }

    /// Names what doesn't fit rather than counting it — «Комплект учебников won't fit»
    /// tells the sender which box to reconsider; «1 item won't fit» sends them looking.
    private static func misfitWords(_ items: [ParcelItem]) -> String {
        let named = items.map { item in
            item.name.trimmingCharacters(in: .whitespaces).isEmpty
                ? String(localized: "one item")
                : item.name
        }
        return String(localized: "Won't fit: \(named.formatted(.list(type: .and)))")
    }
}

#Preview("Card row: priced, and a class the route was not offered") {
    List {
        NewDeliveryView.TariffExplainer.CardRow(
            card: .init(
                name: "Courier",
                emoji: "🛵",
                explanation: "On foot or a scooter",
                limits: ["Up to 10 kg", "80 × 50 × 50 cm"],
                priceText: "749 ₽"
            )
        )
        NewDeliveryView.TariffExplainer.CardRow(
            card: .init(
                name: "Cargo",
                emoji: "🚚",
                explanation: "A van, with loaders if you ask",
                limits: ["Up to 700 kg", "260 × 160 × 150 cm"],
                priceText: nil
            )
        )
    }
}

#Preview("Priced") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.TariffExplainer(cards: [
            .init(
                name: "Courier",
                emoji: "🛵",
                explanation: "On foot or a scooter",
                limits: ["Up to 10 kg", "80 × 50 × 50 cm"],
                priceText: "749 ₽"
            ),
            .init(
                name: "Express",
                emoji: "🚗",
                explanation: "A passenger car",
                limits: ["Up to 20 kg", "100 × 60 × 50 cm"],
                priceText: "1 190 ₽"
            ),
            .init(
                name: "Cargo van",
                emoji: "🚚",
                explanation: "A van, loaders available",
                limits: ["Up to 300 kg · 170 × 96 × 90 cm", "Loaders — one or two"],
                priceText: nil
            ),
        ])
    }
}
