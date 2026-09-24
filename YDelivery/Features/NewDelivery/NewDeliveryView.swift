import SwiftUI
import YDeliveryKit

/// Root view of the New Delivery flow, presented as a sheet — the compose idiom. The draft
/// arrives from `RootView`, which owns it: Close parks the draft rather than destroying
/// it, so the button says Close, not Cancel. Offers and parcel details arrive with the
/// later Phase-2 slices (Roadmap → Phase 2).
struct NewDeliveryView: View {
    let draft: Model
    /// The order is placed and acknowledged — `RootView` retires this draft and closes
    /// the flow.
    let placed: () -> Void
    @State private var showsReview = false
    /// Bumped per confirm — the ordering task's id, so a retry is the same owned task
    /// run again (the Run pattern; attempt 0 no-ops through the model's queue gate).
    @State private var orderAttempt = 0
    /// Bumped by «Check again» on an unresolved acceptance — its own owned run, keyed
    /// like the others so it is cancelled with the screen.
    @State private var reconcileAttempt = 0
    /// Bumped by «Save it again» when history refused a placed order.
    @State private var recordAttempt = 0
    @State private var pickingPoint: Model.Point?
    /// Bumped by the two Retry buttons. Each is part of its task's id, which is what
    /// makes a retry cancellable by the next edit instead of outliving it.
    @State private var estimateAttempt = 0
    @State private var offersAttempt = 0
    @State private var editingItem: ParcelItem?
    @State private var editingOptions: OptionsEditor.Focus?
    @State private var showsExplainer = false
    @Environment(ClientController.self) private var session
    @Environment(StoreController.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// What one priced run answers to: the inputs it prices, and which attempt at them.
    /// Both live tasks are keyed this way, so an edit cancels the stale run and a Retry
    /// is the same owned task run again — never a loose one racing it.
    private struct Run<Inputs: Equatable>: Equatable {
        let inputs: Inputs
        let attempt: Int
    }

    /// The schema sync's key — both the definitions and whether they could be read
    /// at all. An error flip with unchanged definitions must still reach the draft:
    /// it is the difference between "no fields configured" and "schema unread"
    /// (review, PR #42).
    private struct FieldSync: Equatable {
        let definitions: [CustomFieldDefinition]
        let unavailable: Bool
    }

    var body: some View {
        NavigationStack {
            Content(
                rows: contentRows,
                pins: contentPins,
                estimate: draft.estimate,
                offers: draft.offers,
                selectedOfferID: draft.selectedOfferID,
                itemRows: contentItemRows,
                fieldRows: fieldRows(draft.visibleFieldDefinitions),
                hiddenFieldRows: fieldRows(draft.hiddenFieldDefinitions),
                fieldsError: store.fieldsError?.localizedDescription,
                retryFields: { Task { await store.refresh() } },
                optionsSummary: draft.options.summary,
                whenSummary: draft.options.effective().whenSummary,
                commentSummary: draft.options.comment.isEmpty ? nil : draft.options.comment,
                orderBarTitle: orderBarTitle,
                canOrder: draft.selectedOffer != nil,
                canSwap: draft.canSwap,
                canReorder: draft.canReorder,
                pick: { pickingPoint = draft.point(withID: $0) },
                // The same one-flow sheet as the address — a point is one thing, and
                // its editor answers both questions (Round 5, decision #40; author,
                // 2026-09-14). With a place set it opens on Describe.
                editContact: { pickingPoint = draft.point(withID: $0) },
                setRole: { draft.setRole($1, for: $0) },
                swapEnds: { draft.swapEnds() },
                addStop: { pickingPoint = draft.point(withID: draft.addStop()) },
                removeRows: { draft.removePoints(at: $0) },
                moveRows: { draft.movePoints(from: $0, to: $1) },
                retryEstimate: { estimateAttempt += 1 },
                selectOffer: { draft.selectedOfferID = $0 },
                retryOffers: { offersAttempt += 1 },
                openExplainer: { showsExplainer = true },
                // A fresh item exists only in the sheet until Save: cancelling leaves
                // no ghost row behind.
                addItem: { editingItem = ParcelItem() },
                editItem: { editingItem = draft.item(withID: $0) },
                removeItems: { draft.removeItems(at: $0) },
                setFieldValue: { draft.setFieldValue($1, for: $0) },
                revealField: { draft.revealField($0) },
                editOptions: { editingOptions = $0 },
                openReview: { showsReview = true }
            )
            // Structured re-pricing: the ids are what pricing answers to — the route for
            // the estimate; route, parcel, and options for offers — so any edit cancels
            // the stale run and starts the right one; dismissal cancels outright. Each id
            // also carries its Retry's attempt count, so a retry is that same owned task
            // run again rather than a loose one racing it (review, PR #19 and #20).
            .task(id: Run(inputs: draft.routeWaypoints, attempt: estimateAttempt)) {
                await draft.calculateEstimate()
            }
            .task(id: Run(inputs: draft.pricingInputs, attempt: offersAttempt)) {
                await draft.loadOffers { try await session.offers(for: $0) }
            }
            // The ordering run: create → watch → accept, then remember. Owned by its
            // attempt id; the model's queue gate makes appear-time runs no-ops, and a
            // recording failure is said beside the placed state, never swallowed.
            .task(id: orderAttempt) {
                await draft.placeOrder(
                    create: { try await session.createClaim($0, requestID: $1) },
                    watch: { try await session.claimState(id: $0) },
                    accept: { try await session.acceptClaim(id: $0, version: $1) }
                )
                // Recording happens once per placed order. This task re-runs whenever a
                // parked draft is reopened, and `.placed` is still true then.
                if draft.ordering == .placed, !draft.placedOrderIsRecorded,
                   let order = draft.placedOrder {
                    do {
                        try await store.record(
                            order, customFields: draft.customFields(for: order.id),
                            providerObservedAt: .now)
                        draft.notePlacedOrderRecorded()
                    } catch {
                        draft.notePlacedButUnrecorded(error)
                    }
                }
            }
            .task(id: reconcileAttempt) {
                guard reconcileAttempt > 0 else { return }
                await draft.reconcileUnresolved(watch: { try await session.claimState(id: $0) })
                if draft.ordering == .placed, !draft.placedOrderIsRecorded,
                   let order = draft.placedOrder {
                    do {
                        try await store.record(
                            order, customFields: draft.customFields(for: order.id),
                            providerObservedAt: .now)
                        draft.notePlacedOrderRecorded()
                    } catch {
                        draft.notePlacedButUnrecorded(error)
                    }
                }
            }
            .task(id: recordAttempt) {
                guard recordAttempt > 0, draft.ordering == .placed,
                      !draft.placedOrderIsRecorded, let order = draft.placedOrder
                else { return }
                do {
                    try await store.record(
                        order, customFields: draft.customFields(for: order.id),
                        providerObservedAt: .now)
                    draft.notePlacedOrderRecorded()
                } catch {
                    draft.notePlacedButUnrecorded(error)
                }
            }
            .task { await store.refresh() }
            // The «Ваши поля» schema follows the store — an edit mid-draft re-types
            // the section without losing typed values (keyed by definition id), and
            // a read that failed keeps the draft from mistaking unread for empty.
            .task(id: FieldSync(definitions: store.fieldDefinitions,
                                unavailable: store.fieldsError != nil)) {
                draft.fieldDefinitions = store.fieldDefinitions
                draft.fieldsUnavailable = store.fieldsError != nil
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
                        // The flow speaks for the whole point: the place and the
                        // person, or nobody — stated, never inferred.
                        draft.setPlace(place, for: point.id)
                        draft.setContact(contact, for: point.id)
                    },
                    fillEnds: { draft.fillEnds(from: $0, to: $1) }
                )
            }
            .sheet(item: $editingItem) { item in
                ItemEditor(
                    item: item,
                    stops: itemStops,
                    selectedTariff: draft.chosenTariff,
                    save: { draft.setItem($0) }
                )
            }
            .sheet(item: $editingOptions) { focus in
                OptionsEditor(
                    focus: focus,
                    options: draft.options,
                    selectedTariff: draft.chosenTariff,
                    save: { draft.options = $0 }
                )
            }
            .sheet(isPresented: $showsReview) {
                ReviewSheet(
                    stops: reviewStops,
                    itemLines: draft.items.map { item in
                        "\(item.name) — \(item.summary)"
                    },
                    optionsLine: draft.options.summary,
                    // The same `effective()` the order is built from. The sheet is the
                    // last thing the sender reads before an irreversible action, so a
                    // lapsed time shown here while the order departs immediately is the
                    // worst place for the two to disagree (review, PR #22).
                    whenLine: draft.options.effective().whenSummary,
                    tariffName: draft.selectedOffer?.tariff.words ?? "",
                    priceText: draft.selectedOffer?.priceText,
                    blockers: draft.orderBlockers,
                    ordering: draft.ordering,
                    recordWarning: draft.recordWarning,
                    confirm: {
                        draft.confirmOrder()
                        orderAttempt += 1
                    },
                    done: {
                        showsReview = false
                        placed()
                    },
                    // Closes the sheet and nothing else: the draft stays parked with its
                    // token, so a later attempt reuses it rather than buying a second
                    // delivery.
                    unresolvedDone: { showsReview = false },
                    reconcile: { reconcileAttempt += 1 },
                    retryRecording: { recordAttempt += 1 }
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
                addressWarning: point.place?.lacksBuilding == true
                    ? String(localized: "No building number — the courier may have trouble finding the door.")
                    : nil,
                parcelActions: draft.parcelActions(at: index),
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

    var contentItemRows: [Content.ItemRow] {
        draft.items.map { item in
            Content.ItemRow(
                id: item.id,
                name: item.displayName,
                summary: item.summary,
                misfit: draft.selectedOffer.flatMap { offer in
                    offer.tariff.fits(item)
                        ? nil
                        : String(localized: "Doesn't fit \(offer.tariff.words)")
                },
                journey: draft.journeyLine(for: item)
            )
        }
    }

    /// «Ваши поля» reduced to rows — visible fields draw, hidden ones feed the
    /// «Add field» menu (board `4b`). Values live in the draft; this only bridges.
    func fieldRows(_ definitions: [CustomFieldDefinition]) -> [Content.FieldRow] {
        definitions.map { def in
            Content.FieldRow(
                id: def.id,
                name: def.name,
                kind: def.kind,
                choices: draft.fieldChoices(for: def),
                isOptional: def.isOptional,
                value: draft.fieldValues[def.id] ?? ""
            )
        }
    }

    /// The route, restated for the review sheet — same badges, same words.
    var reviewStops: [ReviewSheet.Stop] {
        draft.points.enumerated().compactMap { index, point in
            point.place.map { place in
                ReviewSheet.Stop(
                    id: point.id,
                    badge: PointBadge.Role(
                        role: point.role,
                        index: index,
                        isLast: index == draft.points.count - 1
                    ),
                    address: place.displayAddress,
                    contact: point.contact?.summary ?? ""
                )
            }
        }
    }

    /// The stops an item can board or leave at — labels for the editor's pickers.
    var itemStops: [ItemEditor.Stop] {
        draft.points.compactMap { point in
            point.place.map { ItemEditor.Stop(id: point.id, label: $0.displayAddress) }
        }
    }

    /// Every class the app knows, priced where the strip has a price — the explainer
    /// teaches the vocabulary even for classes the route was not offered.
    /// The CTA's words. `nil` while the bar has no place on screen at all — no route,
    /// no prices asked for yet.
    var orderBarTitle: String? {
        guard draft.offers != .idle else { return nil }
        return draft.selectedOffer.map {
            String(localized: "Order \($0.tariff.words) · \($0.priceText)")
        } ?? String(localized: "Order")
    }

    var explainerCards: [TariffExplainer.Card] {
        let offers: [Offer] = if case .ready(let offers) = draft.offers { offers } else { [] }
        let known: [TariffClass] = [.courier, .express, .cargo]
        let extra = offers.map(\.tariff).filter { !known.contains($0) }
        return (known + extra).map { tariff in
            TariffExplainer.Card(
                tariff: tariff,
                offer: offers.first { $0.tariff == tariff },
                misfits: draft.itemsThatDontFit(tariff),
                parcelIsTooHeavy: draft.parcelIsTooHeavy(for: tariff)
            )
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
    NewDeliveryView(draft: NewDeliveryView.Model(), placed: {})
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(database: nil))
}

#Preview("Route complete") {
    let draft = NewDeliveryView.Model()
    draft.setPlace(
        PickedPlace(latitude: 55.646068, longitude: 37.668176, address: "Москва, ул Москворечье, 6"),
        for: draft.points[0].id
    )
    draft.setContact(
        Contact(givenName: "Иван", familyName: "Петров", phone: "+7 912 345-67-89"),
        for: draft.points[0].id
    )
    draft.setPlace(
        PickedPlace(latitude: 55.652212, longitude: 37.648210, address: "Москва, Каширское шоссе, 52"),
        for: draft.points[1].id
    )
    return NewDeliveryView(draft: draft, placed: {})
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(database: nil))
}

#Preview("Five stops with a return") {
    let draft = NewDeliveryView.Model()
    draft.setPlace(
        PickedPlace(latitude: 59.932720, longitude: 30.349709, address: "Санкт-Петербург, Невский проспект, 100"),
        for: draft.points[0].id
    )
    draft.setContact(
        Contact(givenName: "Менеджер склада", phone: "+7 495 123-45-67", phoneExtension: "123"),
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
    return NewDeliveryView(draft: draft, placed: {})
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(database: nil))
}
