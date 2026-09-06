import SwiftUI
import YDeliveryKit

/// Root view of the New Delivery flow, presented as a sheet — the compose idiom. The draft
/// arrives from `RootView`, which owns it: Close parks the draft rather than destroying
/// it, so the button says Close, not Cancel. Offers and parcel details arrive with the
/// later Phase-2 slices (Roadmap → Phase 2).
struct NewDeliveryView: View {
    let draft: Model
    @State private var pickingPoint: Model.Point?
    /// Bumped by the two Retry buttons. Each is part of its task's id, which is what
    /// makes a retry cancellable by the next edit instead of outliving it.
    @State private var estimateAttempt = 0
    @State private var offersAttempt = 0
    @State private var editingContactPoint: Model.Point?
    @State private var showsExplainer = false
    /// The explainer opens itself once per compose session until the first order exists
    /// (board `3a`); after that it lives behind the ⓘ.
    @State private var hasAutoOpenedExplainer = false
    @Environment(ClientController.self) private var session
    @Environment(StoreController.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The two answers the auto-open needs, so it can be re-asked when either arrives.
    /// Store emptiness is trusted only after a successful read — not knowing is not the
    /// same as knowing there is nothing.
    private struct Onboarding: Equatable {
        let pricesReady: Bool
        let historyKnown: Bool
        let hasOrderedBefore: Bool

        var isBeginnerSeeingPrices: Bool {
            pricesReady && historyKnown && !hasOrderedBefore
        }
    }

    private var onboarding: Onboarding {
        let pricesReady = if case .ready = draft.offers { true } else { false }
        return Onboarding(
            pricesReady: pricesReady,
            historyKnown: store.hasLoaded,
            hasOrderedBefore: store.hasPlacedAnOrder
        )
    }

    /// What one priced run answers to: the inputs it prices, and which attempt at them.
    /// Both live tasks are keyed this way, so an edit cancels the stale run and a Retry
    /// is the same owned task run again — never a loose one racing it.
    private struct Run<Inputs: Equatable>: Equatable {
        let inputs: Inputs
        let attempt: Int
    }

    var body: some View {
        NavigationStack {
            Content(
                rows: contentRows,
                pins: contentPins,
                estimate: draft.estimate,
                offers: draft.offers,
                selectedOfferID: draft.selectedOfferID,
                canSwap: draft.canSwap,
                canReorder: draft.canReorder,
                pick: { pickingPoint = draft.point(withID: $0) },
                editContact: { editingContactPoint = draft.point(withID: $0) },
                setRole: { draft.setRole($1, for: $0) },
                swapEnds: { draft.swapEnds() },
                addStop: { pickingPoint = draft.point(withID: draft.addStop()) },
                removeRows: { draft.removePoints(at: $0) },
                moveRows: { draft.movePoints(from: $0, to: $1) },
                retryEstimate: { estimateAttempt += 1 },
                selectOffer: { draft.selectedOfferID = $0 },
                retryOffers: { offersAttempt += 1 },
                openExplainer: { showsExplainer = true }
            )
            // Structured re-pricing: the ids are the route itself, so any edit cancels
            // the stale runs and starts the right ones; dismissal cancels outright. The
            // estimate's id also carries its attempt count, so Retry re-runs the same
            // owned task rather than a loose one racing it (review, PR #19).
            .task(id: Run(inputs: draft.routeWaypoints, attempt: estimateAttempt)) {
                await draft.calculateEstimate()
            }
            // Offers answer to `offerWaypoints`, not the coordinates: the provider is
            // sent `fullname` beside every pair, so correcting an address without moving
            // the pin changes the price it would quote. Keying on coordinates alone let
            // an edited address keep the old quote, and an order spend it (review, PR #20).
            .task(id: Run(inputs: draft.offerWaypoints, attempt: offersAttempt)) {
                await draft.loadOffers { try await session.offers(for: $0) }
            }
            .task { await store.refresh() }
            // The first prices a beginner ever sees arrive with the explainer open
            // (board 3a). Both inputs matter and either can land last, so the observer
            // watches the pair: keying on the prices alone meant a quote that beat the
            // store's first read failed the test once and was never asked again, and a
            // genuine beginner missed the explainer entirely (review, PR #20).
            .onChange(of: onboarding, initial: true) { _, onboarding in
                guard onboarding.isBeginnerSeeingPrices, !hasAutoOpenedExplainer else { return }
                hasAutoOpenedExplainer = true
                showsExplainer = true
            }
            .sheet(isPresented: $showsExplainer) {
                TariffExplainer(cards: explainerCards)
            }
            .navigationTitle("New Delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $pickingPoint) { point in
                PointPickerView(
                    prompt: point.role.pickerPrompt,
                    initialPlace: point.place,
                    initialContact: point.contact,
                    confirm: { place, contact in
                        draft.setPlace(place, for: point.id)
                        // A remembered point speaks for its own door — including when
                        // nobody is behind it. Refining a pin says nothing, and the row
                        // keeps whoever it had.
                        if case .replace(let contact) = contact {
                            draft.setContact(contact, for: point.id)
                        }
                    },
                    fillEnds: { draft.fillEnds(from: $0, to: $1) }
                )
            }
            .sheet(item: $editingContactPoint) { point in
                ContactEditor(
                    title: point.role.contactPrompt,
                    contact: point.contact ?? Contact(),
                    save: { draft.setContact($0, for: point.id) }
                )
            }
        }
    }
}

// MARK: - Bridging

private extension NewDeliveryView {
    /// The draft, reduced to what the card renders — bridging lives on the root's side
    /// of the seam, so the content view takes plain values only (review, PR #17).
    var contentRows: [Content.Row] {
        let points = draft.points
        return points.enumerated().map { index, point in
            Content.Row(
                id: point.id,
                badge: PointBadge.Role(
                    role: point.role,
                    index: index,
                    isLast: index == points.count - 1
                ),
                address: point.place?.displayAddress,
                placeholder: point.role.pickerPrompt,
                contactSummary: point.contact?.summary,
                contactInvitation: point.role.contactInvitation,
                availableRoles: draft.availableRoles(for: point.id),
                isDeletable: index > 0 && points.count > 2,
                isMovable: index > 0 && point.role != .return
            )
        }
    }

    var contentPins: [Content.Pin] {
        draft.points.enumerated().compactMap { index, point in
            point.place.map { place in
                Content.Pin(
                    id: point.id,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    badge: PointBadge.Role(
                        role: point.role,
                        index: index,
                        isLast: index == draft.points.count - 1
                    )
                )
            }
        }
    }

    /// Every class the app knows, priced where the strip has a price — the explainer
    /// teaches the vocabulary even for classes the route was not offered.
    var explainerCards: [TariffExplainer.Card] {
        let offers: [Offer] = if case .ready(let offers) = draft.offers { offers } else { [] }
        let known: [TariffClass] = [.courier, .express, .cargo]
        let extra = offers.map(\.tariff).filter { !known.contains($0) }
        return (known + extra).map { tariff in
            TariffExplainer.Card(tariff: tariff, offer: offers.first { $0.tariff == tariff })
        }
    }
}

extension NewDeliveryView.Model.Role {
    /// The picker sheet's question, in the sender's words.
    var pickerPrompt: LocalizedStringKey {
        switch self {
        case .pickup: "Where to pick up?"
        case .dropoff: "Where to deliver?"
        case .return: "Where to return?"
        }
    }

    /// The collapsed contact row's invitation — who stands at this door.
    var contactPrompt: LocalizedStringKey {
        switch self {
        case .pickup: "Who hands over"
        case .dropoff: "Who receives"
        case .return: "Who takes the return"
        }
    }
}

#Preview("Empty draft") {
    NewDeliveryView(draft: NewDeliveryView.Model())
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(orderStore: nil, placeStore: nil))
}

#Preview("Route complete") {
    let draft = NewDeliveryView.Model()
    draft.setPlace(
        PickedPlace(latitude: 55.646068, longitude: 37.668176, address: "Москва, ул Москворечье, 6"),
        for: draft.points[0].id
    )
    draft.setContact(
        Contact(name: "Иван Петров", phone: "+7 912 345-67-89"),
        for: draft.points[0].id
    )
    draft.setPlace(
        PickedPlace(latitude: 55.652212, longitude: 37.648210, address: "Москва, Каширское шоссе, 52"),
        for: draft.points[1].id
    )
    return NewDeliveryView(draft: draft)
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(orderStore: nil, placeStore: nil))
}

#Preview("Five stops with a return") {
    let draft = NewDeliveryView.Model()
    draft.setPlace(
        PickedPlace(latitude: 59.932720, longitude: 30.349709, address: "Санкт-Петербург, Невский проспект, 100"),
        for: draft.points[0].id
    )
    draft.setContact(
        Contact(name: "Менеджер склада", phone: "+7 495 123-45-67", phoneExtension: "123"),
        for: draft.points[0].id
    )
    draft.setPlace(
        PickedPlace(latitude: 55.749917, longitude: 37.593450, address: "Москва, Арбат, 10"),
        for: draft.points[1].id
    )
    let third = draft.addStop()
    draft.setPlace(
        PickedPlace(latitude: 55.646068, longitude: 37.668176, address: "Москва, ул Москворечье, 6"),
        for: third
    )
    let fourth = draft.addStop()
    draft.setPlace(
        PickedPlace(latitude: 55.652212, longitude: 37.648210, address: "Москва, Каширское шоссе, 52"),
        for: fourth
    )
    let returnStop = draft.addStop()
    draft.setRole(.return, for: returnStop)
    draft.setPlace(
        PickedPlace(latitude: 59.932720, longitude: 30.349709, address: "Санкт-Петербург, Невский проспект, 100"),
        for: returnStop
    )
    return NewDeliveryView(draft: draft)
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(orderStore: nil, placeStore: nil))
}
