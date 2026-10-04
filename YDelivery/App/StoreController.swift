import CloudKit
import Foundation
import Observation
import OSLog
import SQLiteData
import WidgetKit
import YDeliveryKit

/// The app's window onto the one substrate — orders and saved places, read three ways
/// (recents, chips, and later repeat). Created once in `@main` and injected with
/// `.environment(_:)`; it holds the SQLite database the Phase-2 schema research
/// produced (doc:Schema), the seam that let the UI never notice the JSON files left.
///
/// Being containerless (no App Group in a preview, a broken entitlement) is a state this
/// type exposes for rendering, never a crash.
@Observable @MainActor
final class StoreController {
    private(set) var orders: [Order] = []
    private(set) var savedPlaces: [SavedPlace] = []
    /// The sender's parcel library — the draft's template chips and the Library
    /// tab's Parcels segment read this one list (pinned-first, insertion after).
    private(set) var parcelTemplates: [ParcelTemplate] = []
    /// «Ваши поля» — the sender's field schema (board `4b`), in definition order.
    private(set) var fieldDefinitions: [CustomFieldDefinition] = []
    /// Every stored field value — the search filter, Spotlight, and the detail view
    /// all read this one list rather than per-order queries.
    private(set) var orderFields: [OrderCustomField] = []

    /// The most recent failure reading *orders* — *could not look* must never render
    /// as *nothing there*. Places carry their own channel below: a place save that
    /// succeeds says nothing about whether history is readable, so it must not be able
    /// to clear this (review, PR #18 post-merge).
    private(set) var ordersError: (any Error)?
    /// The most recent failure reading *saved places* — the chips' side of the seam.
    private(set) var placesError: (any Error)?
    /// The fields side of the seam — a schema that failed to read is a draft showing
    /// no fields, which is exactly the state to tell apart from "nothing configured".
    private(set) var fieldsError: (any Error)?
    /// A schema write landed but its confirming read failed — the published
    /// definitions are older than the disk and must not be trusted for validation,
    /// even though they are populated (review, PR #104). Cleared by the next read
    /// of definitions that succeeds, wherever it came from.
    private(set) var fieldsCacheIsStale = false
    /// The write side of the same seam — a gesture the store could not carry. A
    /// reread cannot fix it, so ``refresh()`` leaves it standing; only the next
    /// successful field write clears it.
    private(set) var fieldsWriteError: (any Error)?
    /// The parcel library's side of the seam — same rule: a template list that
    /// could not be read must not render as an empty one (the chip row's
    /// absence would otherwise read as "you have saved nothing").
    private(set) var templatesError: (any Error)?

    /// Whether the store has been read through at least once, successfully. Until it
    /// has, an empty ``orders`` means *not looked yet*, not *nothing there* — and a
    /// first-run surface that reads emptiness as "this sender is new" would greet a
    /// returning one (review, PR #20).
    private(set) var hasLoaded = false
    /// The places file publishes in its own pass after `orders` — a parked
    /// repeat-by-place link needs *this* gate, not the orders' (review, PR #44).
    private(set) var hasLoadedPlaces = false

    private let database: AppDatabase?

    /// The indexing tail of a refresh — serialized so a later wipe can never land
    /// under an earlier add, and never awaited: Spotlight is best-effort, and a
    /// stalled index service (a cold simulator's `searchd` takes a minute to wake)
    /// must not hold the reads' publication or any caller that awaited them.
    private var indexing: Task<Void, Never>?

    /// Field-schema writes queue through this tail: a reorder writes every position,
    /// and a second gesture (move, delete, save) starting mid-write would otherwise
    /// interleave positions into an arrangement nobody chose (review, PR #42).
    private var fieldWrites: Task<Void, Error>?

    /// The widget-snapshot tail — same discipline as ``indexing``: serialized so a
    /// stale render can never land over a fresh one, detached so file I/O never
    /// runs on the actor that owns the published state.
    private var snapshotWrites: Task<Void, Never>?

    /// The saved-places tail — the share extension's «Откуда» row reads
    /// `saved-places.json`, never the database (Schema → the widget contract).
    /// Same discipline as ``snapshotWrites``.
    private var placesWrites: Task<Void, Never>?

    /// The parked draft's write tail — same discipline as ``snapshotWrites``:
    /// the save-on-edit loop lands writes through here, so a consume queued
    /// behind an in-flight save can never be resurrected by it.
    private var draftWrites: Task<Void, Never>?

    /// How many recent orders the snapshot carries — the live set plus a repeat
    /// window, not history at scale: the file is a rendering, small on purpose
    /// (doc:Schema — "the widget contract").
    private nonisolated static let snapshotOrderLimit = 50

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "widget-snapshot")

    private nonisolated static let draftLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "drafts")

    /// Where a healthy read is republished. The store's reads feed three system
    /// surfaces outside its own directory — the Spotlight index, the widget
    /// snapshot in the App Group, the share extension's places file — and those
    /// surfaces belong to *the* app's history, whichever database this instance
    /// happens to read. A store over a fixture (the screenshot seed) must
    /// therefore publish nowhere: an empty first read would otherwise wipe a
    /// real device's widget before the fixtures even land (review, PR #61).
    enum Republication {
        case systemSurfaces
        case none
    }

    private let republication: Republication

    init(database: AppDatabase? = .inAppGroup(
        id: AppGroup.id,
        providerAccountRef: SyncIdentity.providerAccountRef,
        containerIdentifier: SyncIdentity.cloudKitContainer),
         republishing republication: Republication = .systemSurfaces) {
        self.database = database
        self.republication = republication
    }

    /// Whether keeping a place can work at all — the save affordance renders disabled
    /// with its reason when the container is unresolvable, rather than vanishing.
    var canSavePlaces: Bool { database != nil }

    /// Why there is no history to show, when there is none for a reason. A read that
    /// failed and a container that never resolved are different causes with the same
    /// symptom — an empty list — and both must be told apart from "you have not sent
    /// anything yet" (review, PR #18). `nil` when the store is healthy, whether or not
    /// it holds anything.
    var historyUnavailable: String? {
        if let ordersError { return ordersError.localizedDescription }
        if database == nil { return StoreUnavailable().localizedDescription }
        return nil
    }

    /// Why the picker's memory — chips *and* recents — may be missing pieces. The
    /// picker draws on both files (recents from orders, chips from places), so either
    /// error deserves a word there; the deliveries list stays keyed to orders alone.
    /// Without this, a failed place read left chips silently absent while
    /// ``historyUnavailable`` reported health (review, PR #28).
    var pickerMemoryUnavailable: String? {
        if let error = ordersError ?? placesError { return error.localizedDescription }
        if database == nil { return StoreUnavailable().localizedDescription }
        return nil
    }

    /// Whether the sender has ever actually placed an order. The beginner's explainer
    /// runs "until the first successful order" (Roadmap, handoff §7) — and a draft is
    /// precisely an order that was never placed, so counting rows would retire the
    /// explainer for someone who has only ever started one (review, PR #20).
    ///
    /// «Successful» means **accepted by the system**, settled by the author 2026-09-06:
    /// a placed order is part of history whatever becomes of it afterwards, and whether it
    /// was later cancelled or failed to deliver is a question about its status, not about
    /// whether the sender has ordered before. So a cancelled or undelivered order still
    /// counts — they went through the strip and chose a class, which is the vocabulary
    /// this teaches.
    var hasPlacedAnOrder: Bool {
        orders.contains { $0.status != .draft }
    }

    /// The recent points the picker offers: one per address, newest first — an address
    /// delivered to twice is one memory, not two rows (Design → one substrate).
    var recentPoints: [RoutePoint] {
        Self.recentPoints(in: orders, saved: savedPlaces)
    }

    /// Pure and `nonisolated` so the derivation is testable without a controller.
    /// Orders arrive newest-first from the store; the cap keeps the empty-query list
    /// one screen tall (board `2a`).
    ///
    /// Saved places are excluded rather than repeated. Chips and recents are one list
    /// on board `2a`, and a place the sender has named is the same memory with more in
    /// it — offering it again as an anonymous clock row is the "two rows" this
    /// derivation already refuses between recents (review, PR #18).
    nonisolated static func recentPoints(
        in orders: [Order],
        saved: [SavedPlace] = [],
        limit: Int = 8
    ) -> [RoutePoint] {
        var seen = Set(saved.map { $0.point.destinationKey })
        var recents: [RoutePoint] = []
        for point in orders.flatMap(\.route) {
            // The courier's ride home is bookkeeping, not a door the sender sent
            // anything to — recents remember destinations and origins, never it.
            guard point.role != .return else { continue }
            guard !point.address.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard seen.insert(point.destinationKey).inserted else { continue }
            recents.append(point)
            if recents.count == limit { break }
        }
        return recents
    }

    /// Reads both sides off the main actor and publishes the result here — each onto
    /// its own error channel, so one side's failure is never mistaken for the
    /// other's emptiness.
    func refresh() async {
        if let database {
            do {
                orders = try await Self.readOrders(database)
                ordersError = nil
                hasLoaded = true
            } catch {
                ordersError = error
            }
            do {
                savedPlaces = try await Self.readPlaces(database)
                placesError = nil
                hasLoadedPlaces = true
            } catch {
                placesError = error
            }
            do {
                fieldDefinitions = try await Self.readFieldDefinitions(database)
                orderFields = try await Self.readOrderFields(database)
                fieldsError = nil
                fieldsCacheIsStale = false
            } catch {
                fieldsError = error
            }
            do {
                parcelTemplates = try await Self.readParcelTemplates(database)
                templatesError = nil
            } catch {
                templatesError = error
            }
            reindexSpotlightIfHealthy()
            renderWidgetSnapshotIfHealthy()
            publishSavedPlacesIfHealthy()
        } else {
            hasLoaded = true
            hasLoadedPlaces = true
        }
    }

    /// A full-domain replace may only run on healthy reads: a failed read leaves an
    /// empty or stale array published, and indexing that would wipe good results the
    /// disk still holds (review, PR #42). The index keeps its last good state until
    /// the next refresh where every input read succeeded.
    private func reindexSpotlightIfHealthy() {
        guard republication == .systemSurfaces, ordersError == nil, fieldsError == nil else { return }
        reindexSpotlight(orders: orders, fields: orderFields)
    }

    /// Queues the index write behind any in-flight one and returns — the caller's
    /// data is already published; the index catches up on its own clock.
    private func reindexSpotlight(orders: [Order], fields: [OrderCustomField]) {
        let prior = indexing
        indexing = Task {
            await prior?.value
            await SpotlightIndexer.reindex(orders: orders, fields: fields)
        }
    }

    /// The widget contract's writer half: on material change the app renders
    /// `deliveries-snapshot.json` into the App Group and reloads timelines —
    /// the extensions never open the live database (doc:Schema). Same health
    /// gate as the index: a failed read must not let a partial list masquerade
    /// as the truth the widget repeats.
    private func renderWidgetSnapshotIfHealthy() {
        guard republication == .systemSurfaces, ordersError == nil, fieldsError == nil else { return }
        let snapshot = DeliverySnapshot(
            renderedAt: .now,
            orders: Self.snapshotEntries(of: orders, orderNumber: orderNumber(for:)))
        let prior = snapshotWrites
        snapshotWrites = Task.detached {
            await prior?.value
            do {
                try DeliverySnapshotStore.write(snapshot, inAppGroup: AppGroup.id)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                Self.logger.error(
                    "Widget snapshot render failed: \(error.localizedDescription)")
            }
        }
    }

    /// The share extension's places file — the «Откуда» row's whole input,
    /// rendered after each healthy places read so the extension never opens
    /// the database. A failed read must not overwrite good bytes the last
    /// read published: same gate as the index, narrowed to its own channel.
    private func publishSavedPlacesIfHealthy() {
        guard republication == .systemSurfaces, placesError == nil else { return }
        let places = savedPlaces
        let prior = placesWrites
        placesWrites = Task.detached {
            await prior?.value
            do {
                try SavedPlacesFile.write(places, inAppGroup: AppGroup.id)
            } catch {
                Self.logger.error(
                    "Saved-places publish failed: \(error.localizedDescription)")
            }
        }
    }

    /// Which orders the snapshot carries. The cap windows *history*, never
    /// liveness: a delivery started before the newest fifty is still the card
    /// the waiting widget exists for, so live orders ride past the limit
    /// (review, PR #44).
    nonisolated static func snapshotEntries(
        of orders: [Order],
        orderNumber: (Order.ID) -> String?
    ) -> [DeliverySnapshot.Entry] {
        let entry = { DeliverySnapshot.Entry(order: $0, orderNumber: orderNumber($0.id)) }
        return orders.prefix(snapshotOrderLimit).map(entry)
            + orders.dropFirst(snapshotOrderLimit).map(entry).filter(\.isLive)
    }

    /// An order's field values — the detail view and the repeat path read this
    /// filtered view of the one published list.
    func fields(for orderID: Order.ID) -> [OrderCustomField] {
        orderFields.filter { $0.orderID == orderID }
    }

    /// The sender's own number for this order — the value the order-number
    /// carrier carried to the provider — for surfaces that name the order
    /// aloud: a notification title reads «Order №4417», not a UUID. Reads the
    /// value's own `carrier` snapshot: the schema is private-tier, so a shared
    /// order's number must not depend on a definitions join (YD-17).
    func orderNumber(for orderID: Order.ID) -> String? {
        orderFields.first {
            $0.orderID == orderID && $0.carrier == .orderNumber
        }?.value
    }

    /// Keeps a field definition and republishes the schema — the settings editor's
    /// write. Throws like ``save(_:)``: the editor stands in front of the sender and
    /// renders the refusal (a taken carrier) where it happened.
    func saveField(_ definition: CustomFieldDefinition) async throws {
        try await enqueueFieldWrite { try $0.saveFieldDefinition(definition) }
        // The carrier slot may have moved — the index's promoted title follows.
        reindexSpotlightIfHealthy()
        renderWidgetSnapshotIfHealthy()
    }

    /// A reorder writes every position. Serialized behind any in-flight schema write
    /// and republished once at the end — two gestures can then never interleave
    /// positions into an order nobody arranged (review, PR #42).
    func saveFields(_ ordered: [CustomFieldDefinition]) async {
        do {
            try await enqueueFieldWrite { database in
                for (position, definition) in ordered.enumerated() {
                    var definition = definition
                    definition.position = position
                    try database.saveFieldDefinition(definition)
                }
            }
            reindexSpotlightIfHealthy()
            renderWidgetSnapshotIfHealthy()
        } catch {
            fieldsWriteError = error
        }
    }

    /// Forgets a definition — values already on orders keep their name snapshot.
    /// Mirrors ``deletePlace(_:)``: nobody renders a thrown error, so a failure lands
    /// on ``fieldsWriteError``.
    func deleteField(_ id: CustomFieldDefinition.ID) async {
        do {
            try await enqueueFieldWrite { try $0.deleteFieldDefinition(id: id) }
            reindexSpotlightIfHealthy()
            renderWidgetSnapshotIfHealthy()
        } catch {
            fieldsWriteError = error
        }
    }

    /// The schema-write serializer: each caller's work runs after the previous
    /// write finished (a failed one must not strand the queue), then republishes the
    /// schema as the write's own confirmation. The two steps fail differently: a
    /// refused write lands on ``fieldsWriteError`` *and* propagates — the editor
    /// renders it, gestures only record it — while a failed confirming read is a
    /// read failure. The write already landed, so nothing rethrows: ``fieldsError``
    /// says the schema is unreadable and the draft stops believing its stale copy
    /// is the healthy set (review, PR #104).
    private func enqueueFieldWrite(
        _ work: @escaping @concurrent @Sendable (AppDatabase) async throws -> Void
    ) async throws {
        guard let database else { throw StoreUnavailable() }
        let prior = fieldWrites
        let task = Task {
            _ = try? await prior?.value
            do {
                try await work(database)
                fieldsWriteError = nil
            } catch {
                fieldsWriteError = error
                throw error
            }
            do {
                fieldDefinitions = try await Self.readFieldDefinitions(database)
                // The confirming re-read succeeded — the schema is readable and
                // the read error's news is stale.
                fieldsError = nil
                fieldsCacheIsStale = false
            } catch {
                // The write landed; the read is the failure. What is published now
                // predates it — a cache nobody may validate against.
                fieldsError = error
                fieldsCacheIsStale = true
            }
        }
        fieldWrites = task
        try await task.value
    }

    /// Keeps a place and republishes the set.
    ///
    /// This one throws rather than absorbing into ``storeError``, because unlike a refresh
    /// it has a caller standing in front of the sender: the naming sheet, which can stay
    /// open, say what went wrong, and offer the write again. A bookmark that did not
    /// persist must never look like one that did (review, PR #18). The error is a filled
    /// `LocalizedError`, so the sheet renders it as it arrives.
    func save(_ place: SavedPlace) async throws {
        guard let database else { throw StoreUnavailable() }
        try await Self.write(place, to: database)
        do {
            savedPlaces = try await Self.readPlaces(database)
            // That re-read succeeded, so whatever the last refresh recorded about
            // *places* is stale news. Orders were not looked at: their error, if any,
            // stands — a successful bookmark must not dress an unreadable history as
            // an empty one (review, PR #18 post-merge).
            placesError = nil
            publishSavedPlacesIfHealthy()
        } catch {
            // The write held but the confirming read did not: the sheet gets the
            // thrown error to render, and the channel records it — otherwise closing
            // the sheet exposed stale chips as healthy memory (review, PR #28, same
            // truth as record()'s: the write and the read report different facts).
            placesError = error
            throw error
        }
    }

    /// Forgets a place and republishes the chips — the `3e` editor's delete. Unlike
    /// ``save(_:)`` nothing stands in front of the sender to render a thrown error
    /// (a context menu dismisses on selection), so a failure lands on ``placesError``
    /// — the picker's banner reads it — and the chip it meant to remove stays.
    func deletePlace(_ id: SavedPlace.ID) async {
        guard let database else { return }
        do {
            try await Self.deletePlace(id, from: database)
            savedPlaces = try await Self.readPlaces(database)
            placesError = nil
            publishSavedPlacesIfHealthy()
        } catch {
            placesError = error
        }
    }

    /// Whether keeping a template can work at all — the Save-as-template
    /// affordance hides rather than offering a write that cannot run, like
    /// ``canSavePlaces``.
    var canSaveTemplates: Bool { database != nil }

    /// The pin toggle on a remembered door — the chip menu's write and the
    /// Library's. Nobody renders a thrown error, so a failure lands on
    /// ``placesError`` like ``deletePlace(_:)``.
    func setPlacePinned(_ id: SavedPlace.ID, pinned: Bool) async {
        guard let database else { return }
        do {
            try await Self.setPlacePinned(id, pinned: pinned, in: database)
            savedPlaces = try await Self.readPlaces(database)
            placesError = nil
            publishSavedPlacesIfHealthy()
        } catch {
            placesError = error
        }
    }

    /// Keeps a parcel template and republishes the library. Throws like
    /// ``save(_:)``: the naming sheet stands in front of the sender and renders
    /// the refusal where it happened — a template that did not persist must
    /// never look like one that did.
    func save(_ template: ParcelTemplate) async throws {
        guard let database else { throw StoreUnavailable() }
        try await Self.write(template, to: database)
        do {
            parcelTemplates = try await Self.readParcelTemplates(database)
            templatesError = nil
        } catch {
            // The write held but the confirming read did not — same truth as
            // save(place:)'s: only the read may clear the channel.
            templatesError = error
            throw error
        }
    }

    /// One draft item kept as a named template — the write both «Save as a
    /// template» doors share (the editor's affordance and the row menu's
    /// naming sheet), so the row→template mapping lives in one place.
    func saveTemplate(_ item: ParcelItem, name: String) async throws {
        try await save(ParcelTemplate(name: name, items: [item.templateItem]))
    }

    /// Forgets a template — the context menu's write: nobody renders a thrown
    /// error, so a failure lands on ``templatesError`` and the chip stays.
    func deleteTemplate(_ id: ParcelTemplate.ID) async {
        guard let database else { return }
        do {
            try await Self.deleteTemplate(id, from: database)
            parcelTemplates = try await Self.readParcelTemplates(database)
            templatesError = nil
        } catch {
            templatesError = error
        }
    }

    /// The pin toggle on a template — same discipline as ``setPlacePinned``.
    func setTemplatePinned(_ id: ParcelTemplate.ID, pinned: Bool) async {
        guard let database else { return }
        do {
            try await Self.setTemplatePinned(id, pinned: pinned, in: database)
            parcelTemplates = try await Self.readParcelTemplates(database)
            templatesError = nil
        } catch {
            templatesError = error
        }
    }

    /// Records a placed order and republishes history. Throws — an order that was
    /// *placed* but not *remembered* is a state the sender must see, not a silent gap
    /// in the list. `providerObservedAt` marks a provider sighting: callers fresh off
    /// the wire (claim accepted, cancelled, merged) pass it; local writes leave it
    /// nil so the mirror never fabricates freshness.
    func record(_ order: Order, customFields: [OrderCustomField]? = nil,
                providerObservedAt: Date? = nil) async throws {
        guard let database else { throw StoreUnavailable() }
        try await Self.write(
            order, customFields: customFields,
            providerObservedAt: providerObservedAt, to: database)
        // The write held; if the confirming read stumbles, the order still leads the
        // list rather than vanishing until the next refresh — but the write and the
        // read report different facts, and only the read may clear the error: a
        // partial fallback list dressed as healthy history omits orders silently
        // (review, PR #28).
        do {
            orders = try await Self.readOrders(database)
            ordersError = nil
        } catch {
            orders = Self.upserting(order, into: orders)
            ordersError = error
        }
        // Field values are written together with the order; the published cache and
        // the index follow the same read.
        do {
            orderFields = try await Self.readOrderFields(database)
            fieldsError = nil
        } catch {
            fieldsError = error
        }
        reindexSpotlightIfHealthy()
        renderWidgetSnapshotIfHealthy()
    }

    /// The fallback merge when the confirming read fails: the written order kept,
    /// minus any stale copy of itself — recording an *update* (a just-cancelled
    /// order) must not leave its previous status riding along as a second row
    /// (review, PR #32). Sorted like the publish path: an update to an *older*
    /// order must not jump the queue just because it led the write.
    nonisolated static func upserting(_ order: Order, into orders: [Order]) -> [Order] {
        ([order] + orders.filter { $0.id != order.id }).sorted { $0.created > $1.created }
    }

    /// The save-on-edit sink's other end (YD-16): the flow's whole snapshot
    /// lands through the serialized tail, so a save can never lose to an older
    /// in-flight one. Nobody renders a failed draft write — the draft still
    /// works in-session — so a refusal is logged, not thrown.
    func persistDraft(_ draft: OrderDraft) {
        guard let database else { return }
        let prior = draftWrites
        draftWrites = Task.detached {
            await prior?.value
            do {
                try database.saveDraft(draft)
            } catch {
                Self.draftLogger.error(
                    "Draft save failed: \(error.localizedDescription)")
            }
        }
    }

    /// The parked draft, if the substrate holds one — `nil` also when the store
    /// is containerless. A corrupt draft throws inside the store and is logged
    /// here rather than answering "no draft" over bytes it could not read; the
    /// row itself is left alone for the next launch to try again.
    func parkedDraft() async -> OrderDraft? {
        guard let database else { return nil }
        do {
            return try await Self.readDraft(database)
        } catch {
            Self.draftLogger.error(
                "Draft restore failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The draft is consumed — placed, its fate in history's hands. Queued
    /// through the same tail so it lands after every save the loop scheduled.
    func consumeParkedDraft() {
        guard let database else { return }
        let prior = draftWrites
        draftWrites = Task.detached {
            await prior?.value
            do {
                try database.deleteDrafts()
            } catch {
                Self.draftLogger.error(
                    "Draft delete failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Order sharing — the private CKShare door (doc:Collaboration)

    /// Whether the collaboration affordance can work at all — hidden when the
    /// database never resolved, like ``canSavePlaces``.
    var canShareOrders: Bool { database != nil }

    /// The engine `CloudSharingView` binds its participant actions to — its
    /// default pulls a `@Dependency` this app never configures, so the sheet
    /// must be handed the real one explicitly. Nil where the database — or the
    /// engine's own construction — never resolved; the share ask has already
    /// refused by then, so the sheet cannot be up.
    var syncEngine: SyncEngine? { try? database?.syncEngine }

    /// Shares one order privately — or returns its existing share, so the one
    /// button serves "share" and "manage sharing" alike. `title` is the
    /// recipient-facing name the invitation shows. Throws: a share that failed
    /// is one the sender must see fail, not a spinner that pretends (same rule
    /// as ``save(_:)``).
    func shareOrder(_ id: Order.ID, title: String) async throws -> SharedRecord {
        guard let database else { throw StoreUnavailable() }
        return try await database.shareOrder(id: id, title: title)
    }

    /// The recipient side of the door — the scene delegate's tapped share URL
    /// lands here. Accepts through the engine (which pulls the shared zone),
    /// then re-reads the store: ``orders`` is published by ``refresh()`` rather
    /// than observed, so without this pass the just-joined order waits in the
    /// database for the next refresh to notice it (review, PR #56).
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let database else { throw StoreUnavailable() }
        try await database.acceptShare(metadata: metadata)
        await refresh()
    }

    // MARK: The order's chat — the participant-writable stream (doc:Schema)

    /// Whether the chat surface can exist at all — same gate as sharing.
    var canChatOrders: Bool { database != nil }

    /// One order's stream, oldest first — the chat screen's read. Errors travel
    /// up: a stream that cannot be read renders its failure, not an empty chat.
    func messages(for orderID: Order.ID) async throws -> [OrderMessage] {
        guard let database else { throw StoreUnavailable() }
        return try await Self.readMessages(database, orderID: orderID)
    }

    /// Appends to the stream — text, or a structured kind like
    /// `OrderMessage.Kind.receptionConfirmed`. `authorHint` stays nil today:
    /// no account display-name exists in the app yet, and the record's
    /// `createdBy` carries the real attribution regardless.
    func postMessage(_ message: OrderMessage) async throws {
        guard let database else { throw StoreUnavailable() }
        try await Self.writeMessage(message, to: database)
    }

    /// The photo post — attachment, blob, and carrying message in one Kit
    /// transaction (the same-order rule holds by construction there).
    func postPhotoMessage(
        orderID: Order.ID, data: Data, caption: String?
    ) async throws {
        guard let database else { throw StoreUnavailable() }
        try await Self.writePhotoMessage(
            orderID: orderID, data: data, caption: caption, to: database)
    }

    /// One order's provider trail, oldest first — the history row's expanded
    /// timeline. Read on demand, never with the list: a trail per row would
    /// drag every event the journal ever wrote through the list's read.
    func providerEvents(for orderID: Order.ID) async throws -> [ProviderEvent] {
        guard let database else { throw StoreUnavailable() }
        return try await Self.readProviderEvents(database, orderID: orderID)
    }

    /// A photo's bytes, fetched lazily by id — the list never drags image data.
    func attachmentData(_ id: UUID) async throws -> Data? {
        guard let database else { throw StoreUnavailable() }
        return try await Self.readAttachment(id, in: database)
    }

    struct StoreUnavailable: LocalizedError {
        var errorDescription: String? {
            String(localized: "Shared storage is unavailable on this install.")
        }
    }

    // The store is synchronous, serialized SQLite IO — `@concurrent` hops it off the
    // main actor (a plain nonisolated async function would inherit the caller's actor
    // under Approachable Concurrency).

    @concurrent
    private static func readPlaces(_ database: AppDatabase) async throws -> [SavedPlace] {
        try database.readPlaces()
    }

    @concurrent
    private static func readDraft(_ database: AppDatabase) async throws -> OrderDraft? {
        try database.currentDraft()
    }

    @concurrent
    private static func write(_ place: SavedPlace, to database: AppDatabase) async throws {
        try database.savePlace(place)
    }

    @concurrent
    private static func deletePlace(_ id: SavedPlace.ID, from database: AppDatabase) async throws {
        try database.deletePlace(id: id)
    }

    @concurrent
    private static func setPlacePinned(
        _ id: SavedPlace.ID, pinned: Bool, in database: AppDatabase
    ) async throws {
        try database.setPlacePinned(id: id, pinned: pinned)
    }

    @concurrent
    private static func readParcelTemplates(
        _ database: AppDatabase
    ) async throws -> [ParcelTemplate] {
        try database.readParcelTemplates()
    }

    @concurrent
    private static func write(
        _ template: ParcelTemplate, to database: AppDatabase
    ) async throws {
        try database.saveParcelTemplate(template)
    }

    @concurrent
    private static func deleteTemplate(
        _ id: ParcelTemplate.ID, from database: AppDatabase
    ) async throws {
        try database.deleteParcelTemplate(id: id)
    }

    @concurrent
    private static func setTemplatePinned(
        _ id: ParcelTemplate.ID, pinned: Bool, in database: AppDatabase
    ) async throws {
        try database.setParcelTemplatePinned(id: id, pinned: pinned)
    }

    @concurrent
    private static func readOrders(_ database: AppDatabase) async throws -> [Order] {
        try database.readOrders()
    }

    @concurrent
    private static func write(
        _ order: Order,
        customFields: [OrderCustomField]?,
        providerObservedAt: Date?,
        to database: AppDatabase
    ) async throws {
        try database.recordOrder(
            order, customFields: customFields, providerObservedAt: providerObservedAt)
    }

    @concurrent
    private static func readFieldDefinitions(
        _ database: AppDatabase
    ) async throws -> [CustomFieldDefinition] {
        try database.fieldDefinitions()
    }

    @concurrent
    private static func readOrderFields(
        _ database: AppDatabase
    ) async throws -> [OrderCustomField] {
        try database.allOrderCustomFields()
    }

    @concurrent
    private static func readMessages(
        _ database: AppDatabase, orderID: Order.ID
    ) async throws -> [OrderMessage] {
        try database.messages(orderID: orderID)
    }

    @concurrent
    private static func writeMessage(
        _ message: OrderMessage, to database: AppDatabase
    ) async throws {
        try database.postMessage(message)
    }

    @concurrent
    private static func writePhotoMessage(
        orderID: Order.ID, data: Data, caption: String?, to database: AppDatabase
    ) async throws {
        try database.postPhotoMessage(
            orderID: orderID, data: data, caption: caption)
    }

    @concurrent
    private static func readProviderEvents(
        _ database: AppDatabase, orderID: Order.ID
    ) async throws -> [ProviderEvent] {
        try database.providerEvents(orderID: orderID)
    }

    @concurrent
    private static func readAttachment(
        _ id: UUID, in database: AppDatabase
    ) async throws -> Data? {
        try database.attachmentData(id)
    }
}
