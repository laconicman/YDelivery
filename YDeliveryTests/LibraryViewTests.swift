import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

@Suite("Library")
@MainActor
struct LibraryViewTests {
    private typealias Content = LibraryView.Content

    private var place: SavedPlace {
        SavedPlace(
            name: "Office", kind: .shop,
            point: RoutePoint(latitude: 55.7517, longitude: 37.6176,
                              address: "Москва, Николоямская улица, 49с1",
                              contactName: "Иван Петров", contactPhone: "+79123456789"),
            pinned: true)
    }

    private var template: ParcelTemplate {
        ParcelTemplate(
            name: "Keyboard",
            items: [ParcelTemplate.Item(name: "Mechanical keyboard", quantity: 1,
                                        weightKg: 0.9, cost: "4500", currency: "RUB",
                                        sizeLengthCm: 45, sizeWidthCm: 15, sizeHeightCm: 3)])
    }

    @Test("A place row carries the pin, the address and the door's contact")
    func placeRowBridgesTheSavedPlace() {
        let place = place
        let row = Content.PlaceRow(place: place)
        #expect(row.id == place.id)
        #expect(row.name == "Office")
        #expect(row.pinned)
        #expect(row.address == "Москва, Николоямская улица, 49с1")
        #expect(row.contact == "Иван Петров · +79123456789")
        // Search hits the door's contact too, not only the name.
        #expect(row.searchableText.localizedCaseInsensitiveContains("Иван"))
    }

    @Test("A parcel row reads like the row the template stamps")
    func parcelRowSummarisesTheItems() {
        let template = template
        let row = Content.ParcelRow(template: template)
        #expect(row.id == template.id)
        #expect(row.name == "Keyboard")
        #expect(!row.pinned)
        #expect(row.summary.contains("1 pcs"))
        #expect(row.summary.contains("4"))
        #expect(row.searchableText.localizedCaseInsensitiveContains("keyboard"))
    }

    @Test("The typed filter hits name, address and contents, case-insensitively")
    func matchingFiltersBothLists() {
        let places = [Content.PlaceRow(place: place),
                      Content.PlaceRow(place: SavedPlace(name: "Склад", kind: .warehouse,
                                                         point: RoutePoint(latitude: 59, longitude: 30, address: "Невский, 100")))]
        #expect(Content.matching(places, query: "office") == [places[0]])
        #expect(Content.matching(places, query: "НЕВСКИЙ") == [places[1]])
        #expect(Content.matching(places, query: "Петров") == [places[0]])
        // Blank and whitespace queries filter nothing.
        #expect(Content.matching(places, query: "") == places)
        #expect(Content.matching(places, query: "   ") == places)
        #expect(Content.matching(places, query: "moon").isEmpty)

        let parcels = [Content.ParcelRow(template: template),
                       Content.ParcelRow(template: ParcelTemplate(
                        name: "Documents", items: [ParcelTemplate.Item(name: "Papers", currency: "RUB")]))]
        #expect(Content.matching(parcels, query: "doc") == [parcels[1]])
        // Contents are searchable, not only the library name.
        #expect(Content.matching(parcels, query: "mechanical") == [parcels[0]])
    }

    @Test("Editing a template rides the item mapping both ways without loss")
    func editorRoundTripKeepsTheItem() {
        let template = template
        // The editor's init path — template row into the bound item…
        let item = ParcelItem(templateItem: template.items[0])
        // …and its save path back — the two directions must lose nothing.
        let back = item.templateItem
        let original = template.items[0]
        #expect(back.name == original.name)
        #expect(back.quantity == original.quantity)
        #expect(back.weightKg == original.weightKg)
        #expect(back.cost == original.cost)
        #expect(back.currency == original.currency)
        #expect(back.sizeLengthCm == original.sizeLengthCm)
        #expect(back.sizeWidthCm == original.sizeWidthCm)
        #expect(back.sizeHeightCm == original.sizeHeightCm)
    }

    @Test("Editing a place keeps its identity and its pin's ground")
    func editedKeepsIdentityAndGeo() {
        let place = place
        let parts = AddressParts(entrance: "А", floor: "3", apartment: "301")
        let edited = place.edited(name: "Офис", kind: .warehouse, parts: parts,
                                  contact: Contact(at: place.point) ?? Contact())
        #expect(edited.id == place.id)
        #expect(edited.pinned == place.pinned)
        #expect(edited.name == "Офис")
        #expect(edited.kind == .warehouse)
        #expect(edited.point.latitude == place.point.latitude)
        #expect(edited.point.longitude == place.point.longitude)
        #expect(edited.point.address == place.point.address)
        #expect(edited.point.addressParts == parts)
    }

    @Test("Empty door details and an empty contact store as absence")
    func editedStoresEmptinessAsAbsence() {
        let edited = place.edited(name: "Home", kind: .home,
                                  parts: AddressParts(), contact: Contact())
        #expect(edited.point.addressParts == nil)
        #expect(edited.point.contactName == nil)
        #expect(edited.point.contactGivenName == nil)
        #expect(edited.point.contactFamilyName == nil)
        #expect(edited.point.contactPhone == nil)
        #expect(edited.point.contactPhoneExtension == nil)
    }

    @Test("The stored phone lands in E.164 and the name stays componented")
    func editedNormalisesTheContact() {
        let edited = place.edited(
            name: "Home", kind: .home, parts: AddressParts(),
            contact: Contact(givenName: "Иван", familyName: "Петров",
                             phone: "+7 (912) 345-67-89"))
        #expect(edited.point.contactPhone == "+79123456789")
        #expect(edited.point.contactGivenName == "Иван")
        #expect(edited.point.contactFamilyName == "Петров")
        // The formatted whole rides along for the wire and legacy readers —
        // the components are in it; their order is the locale's, not ours.
        #expect(edited.point.contactName?.contains("Иван") == true)
        #expect(edited.point.contactName?.contains("Петров") == true)
    }

    @Test("A save from a stale snapshot never moves the pin")
    func staleSnapshotSaveKeepsThePin() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LibraryViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = StoreController(
            database: AppDatabase(directory: directory, providerAccountRef: "test:unattributed", containerIdentifier: "iCloud.test"),
            republishing: .none)

        // The suite's place is pinned; the store's copy starts unpinned.
        var unpinned = place
        unpinned.pinned = false
        try await store.save(unpinned)
        await store.refresh()
        guard let saved = store.savedPlaces.first else {
            Issue.record("A saved place must be readable")
            return
        }
        await store.setPlacePinned(saved.id, pinned: true)
        #expect(store.savedPlaces.first?.pinned == true)

        // `saved` was captured before the pin — its snapshot says false, exactly
        // like a sheet opened before the toggle. The save must not revert it.
        try await store.save(saved.edited(name: "Склад", kind: .warehouse,
                                        parts: AddressParts(), contact: Contact()))
        #expect(store.savedPlaces.first?.pinned == true)
        #expect(store.savedPlaces.first?.name == "Склад")

        // A *new* place's pin is still honoured — the rebasing touches known ids only.
        try await store.save(SavedPlace(
            name: "Дом", kind: .home,
            point: RoutePoint(latitude: 59, longitude: 30, address: "Невский, 100"),
            pinned: true))
        #expect(store.savedPlaces.first(where: { $0.name == "Дом" })?.pinned == true)
    }

    @Test("Pinning and forgetting a template ride the store")
    func templatePinAndDelete() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LibraryViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = StoreController(
            database: AppDatabase(directory: directory, providerAccountRef: "test:unattributed", containerIdentifier: "iCloud.test"),
            republishing: .none)

        try await store.save(template)
        await store.refresh()
        guard let saved = store.parcelTemplates.first else {
            Issue.record("A saved template must be readable")
            return
        }
        await store.setTemplatePinned(saved.id, pinned: true)
        #expect(store.parcelTemplates.first?.pinned == true)
        await store.setTemplatePinned(saved.id, pinned: false)
        #expect(store.parcelTemplates.first?.pinned == false)
        await store.deleteTemplate(saved.id)
        #expect(store.parcelTemplates.isEmpty)
    }
}
