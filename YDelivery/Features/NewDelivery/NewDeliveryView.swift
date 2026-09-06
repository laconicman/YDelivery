import SwiftUI
import YDeliveryKit

/// Root view of the New Delivery flow, presented as a sheet — the compose idiom. The draft
/// arrives from `RootView`, which owns it: Close parks the draft rather than destroying
/// it, so the button says Close, not Cancel. Offers and parcel details arrive with the
/// later Phase-2 slices (Roadmap → Phase 2).
struct NewDeliveryView: View {
    let draft: Model
    @State private var pickingPoint: Model.Point?
    /// Bumped by Retry. It is part of the estimate task's id, which is what makes a
    /// retry cancellable by the next route edit instead of outliving it.
    @State private var estimateAttempt = 0
    @State private var editingContactPoint: Model.Point?
    @Environment(\.dismiss) private var dismiss

    /// What one estimate run answers to. Route edits and retries both change it, so
    /// exactly one calculation is ever live and the last one to start is the one that
    /// publishes.
    private struct EstimateRun: Equatable {
        let waypoints: [RouteEstimate.Coordinate]
        let attempt: Int
    }

    var body: some View {
        NavigationStack {
            Content(
                rows: contentRows,
                pins: contentPins,
                estimate: draft.estimate,
                canSwap: draft.canSwap,
                canReorder: draft.canReorder,
                pick: { pickingPoint = draft.point(withID: $0) },
                editContact: { editingContactPoint = draft.point(withID: $0) },
                setRole: { draft.setRole($1, for: $0) },
                swapEnds: { draft.swapEnds() },
                addStop: { pickingPoint = draft.point(withID: draft.addStop()) },
                removeRows: { draft.removePoints(at: $0) },
                moveRows: { draft.movePoints(from: $0, to: $1) },
                retryEstimate: { estimateAttempt += 1 }
            )
            // Structured re-estimation: the id is the route plus which attempt at it, so
            // any edit cancels the stale run and starts the right one, dismissal cancels
            // outright — and a retry is the same owned task run again rather than a loose
            // one racing it (review, PR #19).
            .task(id: EstimateRun(waypoints: draft.routeWaypoints, attempt: estimateAttempt)) {
                await draft.calculateEstimate()
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
}
