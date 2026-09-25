import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// YD-16's app half: the draft parks on disk through `persistedDraft` and comes
/// back through `init(restoring:)`; the save-on-edit loop is the same seam,
/// debounced. Everything below is offline — the substrate is a temp
/// `AppDatabase`, the loop's clock is a short sleep.
@Suite("Draft persistence")
@MainActor
struct DraftPersistenceTests {
    private let directory: URL

    init() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DraftPersistenceTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    private func makeStore() -> StoreController {
        StoreController(database: AppDatabase(
            directory: directory, providerAccountRef: "test:unattributed",
            containerIdentifier: "iCloud.test"))
    }

    /// A draft exercising every persisted lane: filled pickup with a contact, an
    /// unfilled middle hole, a return, a parcel with a named journey, options off
    /// their defaults, a chosen class, and a revealed-but-empty field.
    private func fullModel() -> NewDeliveryView.Model {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        let pickupID = model.points[0].id
        // [pickup, dropoff] → add the hole → reflag the middle as the return:
        // [pickup, hole, return].
        let holeID = model.addStop()
        let returnID = model.points[1].id
        model.setRole(.return, for: returnID)
        model.setPlace(
            PickedPlace(latitude: 55.7558, longitude: 37.6173,
                        address: "Москва, Тверская 1",
                        parts: AddressParts(entrance: "2", floor: "", apartment: "15", intercom: "77")),
            for: pickupID)
        model.setContact(
            Contact(givenName: "Иван", familyName: "Петров",
                    phone: "+79123456789", phoneExtension: "12"),
            for: pickupID)
        var item = ParcelItem()
        item.name = "Коробка"
        item.quantity = 2
        item.weightKg = 3.5
        item.cost = 2500.50
        item.currency = "RUB"
        item.size = ParcelItem.Size(lengthCm: 25, widthCm: 18, heightCm: 15)
        item.pickupPointID = holeID
        item.dropoffPointID = returnID
        model.setItem(item)
        model.options.proCourier = true
        model.options.thermobag = true
        model.options.loaders = 2
        model.options.due = Date(timeIntervalSince1970: 1_800_003_600)
        model.options.comment = "Домофон не работает"
        let fieldID = UUID()
        model.fieldValues[fieldID] = "Заказ 4417"
        model.revealField(UUID())
        return model
    }

    @Test("A parked draft restores whole — route, parcel, options, fields")
    func roundTrip() {
        let model = fullModel()
        let holeID = model.points[1].id
        let returnID = model.points[2].id

        let restored = NewDeliveryView.Model(restoring: model.persistedDraft)

        #expect(restored.draftID == model.draftID)
        #expect(restored.points.map(\.id) == model.points.map(\.id))
        #expect(restored.points.map(\.role) == [.pickup, .dropoff, .return])
        #expect(restored.points[0].place?.address == "Москва, Тверская 1")
        #expect(restored.points[0].place?.parts?.entrance == "2")
        #expect(restored.points[0].contact?.fullName == "Иван Петров")
        #expect(restored.points[0].contact?.phoneExtension == "12")
        #expect(restored.points[1].place == nil, "the hole stays a hole")
        let item = restored.items.first
        #expect(item?.name == "Коробка" && item?.quantity == 2)
        #expect(item?.cost == 2500.50 && item?.weightKg == 3.5)
        #expect(item?.size?.heightCm == 15)
        #expect(item?.pickupPointID == holeID && item?.dropoffPointID == returnID,
                "the named journey survives")
        #expect(restored.options.proCourier && restored.options.thermobag)
        #expect(restored.options.loaders == 2)
        #expect(restored.options.due == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(restored.options.comment == "Домофон не работает")
        #expect(restored.fieldValues == model.fieldValues)
        #expect(restored.revealedFieldIDs == model.revealedFieldIDs)
    }

    @Test("The chosen class comes back so repricing re-offers it")
    func tariffRestores() {
        let model = NewDeliveryView.Model()
        var draft = model.persistedDraft
        draft.chosenTariff = "cargo"
        let restored = NewDeliveryView.Model(restoring: draft)
        #expect(restored.chosenTariff == .cargo)
    }

    @Test("A stored route the invariants can't carry restores as a fresh one")
    func invalidRouteFallsBack() {
        var draft = OrderDraft()
        draft.stops = [OrderDraft.Stop(role: "dropoff")]  // one stop, no pickup
        draft.comment = "kept"
        let restored = NewDeliveryView.Model(restoring: draft)
        #expect(restored.points.count == 2)
        #expect(restored.points[0].role == .pickup)
        #expect(restored.options.comment == "kept",
                "the route falls back; the rest of the draft still restores")

        draft.stops = [
            OrderDraft.Stop(role: "pickup"),
            OrderDraft.Stop(role: "pickup"),  // only the route's start picks up
            OrderDraft.Stop(role: "dropoff"),
        ]
        let midPickup = NewDeliveryView.Model(restoring: draft)
        #expect(midPickup.points.count == 2)
        #expect(midPickup.points[0].role == .pickup)
    }

    @Test("A journey naming a gone stop is repaired, not kept dangling")
    func danglingJourneyRepairs() {
        var draft = OrderDraft()
        draft.stops = [
            OrderDraft.Stop(role: "pickup"),
            OrderDraft.Stop(role: "dropoff"),
        ]
        var item = OrderDraft.Item(currency: "RUB")
        item.pickupStopRef = UUID()  // names no stop in the route
        draft.items = [item]
        let restored = NewDeliveryView.Model(restoring: draft)
        #expect(restored.items.first?.pickupPointID == nil,
                "nil reads as the route's end — the honest repair")
    }

    @Test("Pristine is the untouched founding draft only")
    func pristineGate() {
        let model = NewDeliveryView.Model()
        #expect(model.isPristineDraft)
        _ = model.addStop()
        #expect(!model.isPristineDraft, "an added hole is still the sender's work")
    }

    @Test("An armed draft writes after the debounce, edits coalesced")
    func saveOnEditDebounces() async throws {
        var snapshots: [OrderDraft] = []
        let model = NewDeliveryView.Model()
        model.persistDraftChanges { snapshots.append($0) }
        #expect(snapshots.isEmpty, "a pristine draft parks nothing")

        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"),
                       for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.76, longitude: 37.62, address: "Б"),
                       for: model.points[1].id)
        try await Task.sleep(for: .milliseconds(600))
        #expect(snapshots.count == 1, "two edits inside the window write once")
        #expect(snapshots.first?.stops.count == 2)
    }

    @Test("A content-bearing draft parks at once; a consumed one cannot resurrect")
    func armSavesAndStopDisarms() async throws {
        var snapshots: [OrderDraft] = []
        let model = fullModel()
        model.persistDraftChanges { snapshots.append($0) }
        #expect(snapshots.count == 1, "arming on content writes without an edit")

        model.stopPersistingDraft()
        model.options.comment = "typed after the consume"
        try await Task.sleep(for: .milliseconds(600))
        #expect(snapshots.count == 1, "a disarmed loop writes nothing")
    }

    @Test("Flush writes now — the background sweep's half")
    func flushWritesImmediately() {
        var snapshots: [OrderDraft] = []
        let model = NewDeliveryView.Model()
        model.persistDraftChanges { snapshots.append($0) }
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"),
                       for: model.points[0].id)
        model.flushPersistedDraft()
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.stops.first?.point?.address == "А")
    }

    @Test("The store end round-trips a parked draft and consumes it")
    func storeEndToEnd() async throws {
        let store = makeStore()
        let model = fullModel()
        store.persistDraft(model.persistedDraft)

        // The tail is fire-and-forget — poll until the write lands.
        var restored: OrderDraft?
        for _ in 0..<50 where restored == nil {
            restored = await store.parkedDraft()
            if restored == nil { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(restored?.comment == "Домофон не работает")
        #expect(restored?.stops.count == 3)

        store.consumeParkedDraft()
        var gone = false
        for _ in 0..<50 where !gone {
            gone = await store.parkedDraft() == nil
            if !gone { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(gone)
    }

    @Test("A consume queued behind an in-flight save lands last")
    func consumeAfterSave() async throws {
        let store = makeStore()
        store.persistDraft(fullModel().persistedDraft)
        store.consumeParkedDraft()
        // The tail is microseconds; the delay only has to outlive it. If the
        // delete had lost the ordering, the save would have resurrected a row.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await store.parkedDraft() == nil)
    }

    struct Unexpected: Error {}
}
