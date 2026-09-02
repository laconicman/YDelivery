import SwiftUI

/// Root view of the New Delivery flow, presented as a sheet — the compose idiom. The draft
/// arrives from `RootView`, which owns it: Close parks the draft rather than destroying
/// it, so the button says Close, not Cancel. Offers and parcel details arrive with the
/// later Phase-2 slices (Roadmap → Phase 2).
struct NewDeliveryView: View {
    let draft: Model
    @State private var pickingPoint: Model.Point?
    @State private var editingContactPoint: Model.Point?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Content(
                draft: draft,
                pick: { pickingPoint = draft.point(withID: $0) },
                editContact: { editingContactPoint = draft.point(withID: $0) },
                setRole: { draft.setRole($1, for: $0) },
                swapEnds: { draft.swapEnds() },
                addStop: { pickingPoint = draft.point(withID: draft.addStop()) },
                removeRows: { draft.removePoints(at: $0) },
                moveRows: { draft.movePoints(from: $0, to: $1) }
            )
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
                    confirm: { place, contact in
                        draft.setPlace(place, for: point.id)
                        // A chip or recent brings its person along; a bare place never
                        // erases somebody already standing at the door.
                        if let contact {
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
