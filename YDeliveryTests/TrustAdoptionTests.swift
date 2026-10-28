import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// An authority that plays CloudKit's part for the app's tests, as the Kit's own
/// suites do: CloudKit's creator stamps and shares cannot be made through public API,
/// so ownership and the roster are given per order, and this device's key is the
/// only one it binds. An order it is not told about is private (`.local`).
struct FakeAuthority: IdentityAuthority {
    var localParty: UUID?
    var myKeyID: String?
    var owners: [Order.ID: Ownership] = [:]
    var participants: [Order.ID: [Member]] = [:]
    /// The name the roster gives the owner — what an unshared order must never show.
    var ownerName: String?

    func binding(of key: ParticipantKey) -> KeyBinding {
        key.keyID == myKeyID ? .mine : .none
    }

    func owner(of orderID: Order.ID) -> Ownership {
        owners[orderID] ?? .local
    }

    func members(of orderID: Order.ID) -> [Member] {
        guard case .party(let owner) = owners[orderID] else { return [] }
        return [Member(ref: owner, canWrite: true, displayName: ownerName, isOwner: true)]
            + (participants[orderID] ?? [])
    }
}

/// The app's adoption of the trust layer (doc:Collaboration → "Sign facts, derive
/// state"): writes attributed to the local party, the share mirrored into membership
/// rows, the attested reads with no names on an unshared order, and the launches that
/// never learn a party. No CloudKit: the authority is the fake above.
@Suite("Trust layer adoption")
@MainActor
struct TrustAdoptionTests {
    private let keys = EphemeralKeyStore()
    private let me = UUID.partyRef(authority: CloudKitIdentityAuthority.authorityKind, subject: "_me")

    private func makeDatabase() -> AppDatabase {
        AppDatabase(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("trust-\(UUID().uuidString)", isDirectory: true),
            providerAccountRef: "test:unattributed", containerIdentifier: "iCloud.test",
            keyStore: keys)
    }

    private func order(_ claimID: String) -> Order {
        Order(
            created: Date(timeIntervalSince1970: 1_800_000_000), status: .active,
            route: [RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6"),
                    RoutePoint(latitude: 55.76, longitude: 37.59, address: "Арбат, 1")],
            claimID: claimID)
    }

    private func authority(_ configure: (inout FakeAuthority) -> Void = { _ in }) throws -> FakeAuthority {
        var authority = FakeAuthority(localParty: me, myKeyID: try keys.signatory().keyID)
        configure(&authority)
        return authority
    }

    @Test("Messages, photos and the placed fact are attributed to the local party, whatever the caller passed")
    func writesAreAttributed() async throws {
        let database = makeDatabase()
        let store = StoreController(database: database, authority: try authority(), republishing: .none)
        let placedOrder = order("claim-a")
        let placed = try #require(OrderEvent.placed(
            placedOrder, observed: .init(at: Date(timeIntervalSince1970: 1_800_000_040), revision: 3)))
        try await store.record(placedOrder, placed: placed)
        try await store.record(placedOrder, placed: placed)
        let events = try database.events(orderID: placedOrder.id)
        #expect(events.count == 1, "a retried record re-derives the same fact")
        #expect(events.first?.kind == OrderEvent.Kind.placed && events.first?.authorRef == me)

        try await store.postMessage(OrderMessage(
            orderID: placedOrder.id, kind: OrderMessage.Kind.text, text: "у ворот", authorRef: UUID()))
        try await store.postPhotoMessage(orderID: placedOrder.id, data: Data([1, 2, 3]), caption: nil)
        #expect(try database.messages(orderID: placedOrder.id).map(\.authorRef) == [me, me])
        let attested = try await store.attestedMessages(for: placedOrder.id)
        #expect(attested.allSatisfy { $0.verdict.isVerified })
    }

    @Test("The share mirror writes for owned shared orders only, and a second pass writes nothing")
    func reconcileRunsForOwnedSharesOnly() async throws {
        let database = makeDatabase()
        let owned = order("claim-owned"), joined = order("claim-joined"), solo = order("claim-solo")
        let irina = UUID.partyRef(authority: CloudKitIdentityAuthority.authorityKind, subject: "_irina")
        let them = UUID.partyRef(authority: CloudKitIdentityAuthority.authorityKind, subject: "_them")
        let store = StoreController(database: database, authority: try authority {
            $0.owners = [owned.id: .party(me), joined.id: .party(them)]
            $0.participants = [owned.id: [Member(ref: irina, canWrite: true)],
                               joined.id: [Member(ref: me, canWrite: true)]]
        }, republishing: .none)
        for order in [owned, joined, solo] { try await store.record(order) }

        #expect(await store.reconcileMemberships() == MembershipReconciliation(mirrored: 1, removed: 0))
        #expect(try database.memberships(orderID: owned.id).map(\.partyRef) == [irina])
        #expect(try database.memberships(orderID: joined.id).isEmpty, "a share this device joined is its owner's to mirror")
        #expect(try database.memberships(orderID: solo.id).isEmpty, "a private order has nobody to mirror")
        #expect(await store.reconcileMemberships() == MembershipReconciliation(mirrored: 0, removed: 0))
    }

    @Test("An unshared order returns no names: no members, and its verdicts name nobody")
    func unsharedOrderNamesNobody() async throws {
        let database = makeDatabase()
        let placedOrder = order("claim-private")
        let authority = try authority {
            $0.owners = [placedOrder.id: .party(me)]
            $0.ownerName = "Отправитель"
        }
        let store = StoreController(database: database, authority: authority, republishing: .none)
        try await store.record(placedOrder)
        try await store.postMessage(OrderMessage(orderID: placedOrder.id, kind: OrderMessage.Kind.text, text: "здесь"))
        // The precondition: the authority would name the writer if asked.
        #expect(try database.attestedMessages(orderID: placedOrder.id, authority: authority)
            .first?.verdict.author?.displayName == "Отправитель")

        let messages = try await store.attestedMessages(for: placedOrder.id)
        #expect(messages.count == 1 && messages[0].verdict.isVerified)
        #expect(messages[0].verdict.author?.ref == me && messages[0].verdict.author?.displayName == nil)
        #expect(try await store.members(of: placedOrder.id).isEmpty)
    }

    @Test("The identity note is skipped on the schema-seed and fixture launches")
    func identityNoteSkipsSeedLaunches() {
        #expect(YDeliveryApp.notesLocalParty(launchArguments: ["YDelivery"]))
        for flag in [YDeliveryApp.cloudKitSeedFlag, YDeliveryApp.cloudKitSeedCleanFlag,
                     YDeliveryApp.historyFixtureFlag] {
            #expect(!YDeliveryApp.notesLocalParty(launchArguments: ["YDelivery", flag]), "\(flag)")
        }
    }
}
