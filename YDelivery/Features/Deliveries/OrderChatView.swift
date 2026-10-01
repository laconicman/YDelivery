import PhotosUI
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

/// Root view of the order's chat — the participant-writable stream
/// (doc:Schema → `OrderMessage`). Anyone holding the order's share posts here;
/// the stream is append-only by convention, so the screen only ever appends.
struct OrderChatView: View {
    let order: Order
    @Environment(StoreController.self) private var store
    @State private var model = Model()
    /// The draft message — a successful send consumes it, a failed one keeps it
    /// (the token field's own rule, SettingsView).
    @State private var composer = ""

    var body: some View {
        Content(
            messages: model.messages,
            photoData: model.photoData,
            loadError: model.loadError,
            sendError: model.sendError,
            isSending: model.isSending,
            composer: $composer,
            send: sendText,
            confirmReceipt: confirmReceipt,
            sendPhoto: sendPhoto,
            photo: { model.photo($0, using: store.attachmentData) }
        )
        .navigationTitle(Text("Chat"))
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        await model.load { try await store.messages(for: order.id) }
    }

    /// Only a landed post consumes the draft — a failed send keeps the typed
    /// text so retrying is not a retype (SettingsView's own rule). And only an
    /// untouched draft clears: typing mid-send is newer intent, not residue.
    private func sendText() {
        let draft = composer
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            let sent = await model.post(
                OrderMessage(
                    orderID: order.id, kind: OrderMessage.Kind.text, text: text),
                using: store.postMessage,
                then: { try await store.messages(for: order.id) })
            if sent, composer == draft { composer = "" }
        }
    }

    private func confirmReceipt() {
        Task {
            _ = await model.post(
                OrderMessage(
                    orderID: order.id,
                    kind: OrderMessage.Kind.receptionConfirmed),
                using: store.postMessage,
                then: { try await store.messages(for: order.id) })
        }
    }

    /// The picker's selection → bytes → the post. A transfer that never
    /// delivers `Data` surfaces as a send failure, not silence.
    private func sendPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self)
                else { throw PhotoTransferFailed() }
                _ = await model.postPhoto(
                    orderID: order.id, data: data,
                    using: store.postPhotoMessage,
                    then: { try await store.messages(for: order.id) })
            } catch {
                model.noteSendError(error)
            }
        }
    }
}

/// The picker agreed and delivered nothing — an empty pick, not a post.
private struct PhotoTransferFailed: LocalizedError {
    var errorDescription: String? {
        String(localized: "The selected photo could not be loaded.")
    }
}

extension OrderChatView {
    /// The screen's async owner (rule 6): the read is cancellable with the
    /// screen, posts are single-flight and survive the screen — a message half
    /// sent and abandoned is the failure this discipline exists against.
    @Observable @MainActor
    final class Model {
        /// `nil` until the first read lands — loading and empty are different
        /// states (the empty stream invites the first word, not an error).
        private(set) var messages: [OrderMessage]?
        /// Photo payloads by attachment id — fetched lazily as rows appear.
        private(set) var photoData: [UUID: Data] = [:]
        private(set) var loadError: String?
        private(set) var sendError: String?
        private(set) var isSending = false

        private var loading: Task<Void, Never>?
        /// Stream-reader epoch — every read (a load, a post's re-read) is born
        /// at one value; the three counters below decide whether its result
        /// may still publish when it lands (the same race `OrderDetailView`
        /// guards).
        private var generation = 0
        /// The epoch whose read actually published `messages` — a superseded
        /// read still lands when the newer attempt produced nothing (a failed
        /// refresh must not cost a post its snapshot).
        private var appliedStream = 0
        /// The epoch of the last write that landed. A read born *before* it
        /// photographed a stream without that row — its snapshot is stale
        /// however it fares, and must not publish over the post's own account
        /// (review, PR #58: a pre-post load dressing the stream as empty and
        /// healthy after the post's re-read failed).
        private var lastWrite = 0
        /// A photo fetch already asked for — rows re-ask on every render, and
        /// the fetch itself is what must not repeat.
        private(set) var photoRequests: Set<UUID> = []
        /// The payload fetcher, remembered so a stream reload can re-ask for
        /// references still missing bytes — a placeholder must heal on pull.
        private var photoFetch: ((UUID) async throws -> Data?)?

        func load(using fetch: @escaping () async throws -> [OrderMessage]) async {
            loading?.cancel()
            generation += 1
            let born = generation
            loading = Task {
                defer { if born == generation { loading = nil } }
                do {
                    let fetched = try await fetch()
                    guard mayPublish(born) else { return }
                    messages = fetched
                    appliedStream = born
                    loadError = nil
                    reaskMissingPhotos()
                } catch {
                    guard mayPublish(born) else { return }
                    loadError = Self.describe(error)
                }
            }
            await loading?.value
        }

        /// Whether a read born at `born` may still speak: no newer read has
        /// published, no write landed after it began, and its caller has not
        /// moved on — a cancelled read has no seat to publish into, success or
        /// failure alike.
        private func mayPublish(_ born: Int) -> Bool {
            appliedStream <= born && lastWrite <= born && !Task.isCancelled
        }

        /// Posts one entry and re-reads the stream — the read is local and
        /// cheap, and it is how the posted row arrives in its sorted seat.
        /// Returns whether the post landed; the caller consumes its draft then.
        /// A landed post whose re-read failed still counts: retrying a send
        /// that already wrote would duplicate the row.
        func post(
            _ message: OrderMessage,
            using post: (OrderMessage) async throws -> Void,
            then reload: () async throws -> [OrderMessage]
        ) async -> Bool {
            await runPost({ try await post(message) }, then: reload)
        }

        func postPhoto(
            orderID: Order.ID, data: Data,
            using post: (Order.ID, Data, String?) async throws -> Void,
            then reload: () async throws -> [OrderMessage]
        ) async -> Bool {
            await runPost({ try await post(orderID, data, nil) }, then: reload)
        }

        /// Single-flight write → re-read. Two failure doors, kept apart: the
        /// write's failure keeps the caller's draft; the re-read's failure is
        /// a stale stream over a sent row — `loadError`, and pull-to-refresh
        /// heals it.
        private func runPost(
            _ write: () async throws -> Void,
            then reload: () async throws -> [OrderMessage]
        ) async -> Bool {
            guard !isSending else { return false }
            isSending = true
            defer { isSending = false }
            sendError = nil
            do {
                try await write()
            } catch {
                sendError = Self.describe(error)
                return false
            }
            generation += 1
            let born = generation
            lastWrite = born
            do {
                let fetched = try await reload()
                // Publish unless a genuinely newer read already did — a
                // superseding load that failed produced nothing, and this
                // snapshot is still the freshest that exists. (`lastWrite`
                // is this very epoch, so only the publication check applies.)
                guard appliedStream <= born else { return true }
                messages = fetched
                appliedStream = born
                loadError = nil
                reaskMissingPhotos()
            } catch {
                guard appliedStream <= born else { return true }
                loadError = Self.describe(error)
            }
            return true
        }

        /// A photo's bytes, asked once per attachment — a nil answer (payload
        /// still syncing) leaves the frame a placeholder, and the next stream
        /// reload re-asks via `reaskMissingPhotos`.
        func photo(_ id: UUID, using fetch: @escaping (UUID) async throws -> Data?) {
            photoFetch = fetch
            guard photoData[id] == nil, !photoRequests.contains(id) else { return }
            photoRequests.insert(id)
            let born = generation
            Task {
                let data = try? await fetch(id)
                photoRequests.remove(id)
                if let data {
                    photoData[id] = data
                } else if born != generation {
                    // The stream refreshed mid-flight — this nil is stale, so
                    // one re-ask under the new epoch heals the placeholder.
                    photo(id, using: fetch)
                }
            }
        }

        /// A failure outside a post — a photo that never became `Data`.
        func noteSendError(_ error: any Error) {
            sendError = Self.describe(error)
        }

        /// Payloads the fresh stream still lacks — `photo` dedupes the ones
        /// already flying, so re-asking the whole stream is cheap.
        private func reaskMissingPhotos() {
            guard let photoFetch else { return }
            for message in messages ?? [] {
                if let ref = message.attachmentRef { photo(ref, using: photoFetch) }
            }
        }

        private static func describe(_ error: any Error) -> String {
            (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Chat — with a stream") {
    let order = Order.previewDone
    let database = AppDatabase(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true),
        providerAccountRef: "preview:test",
        containerIdentifier: "iCloud.preview")
    try? database.recordOrder(order)
    try? database.postMessage(OrderMessage(
        orderID: order.id, kind: OrderMessage.Kind.text,
        text: "The courier is at the gate", authorHint: "Irina"))
    try? database.postMessage(OrderMessage(
        orderID: order.id, kind: OrderMessage.Kind.receptionConfirmed,
        authorHint: "Irina"))
    return NavigationStack {
        OrderChatView(order: order)
            .environment(StoreController(database: database))
    }
}

#Preview("Chat — empty") {
    let order = Order.previewDone
    let database = AppDatabase(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true),
        providerAccountRef: "preview:test",
        containerIdentifier: "iCloud.preview")
    try? database.recordOrder(order)
    return NavigationStack {
        OrderChatView(order: order)
            .environment(StoreController(database: database))
    }
}

#Preview("Chat — storage unavailable") {
    NavigationStack {
        OrderChatView(order: .previewDone)
            .environment(StoreController(database: nil))
    }
}
#endif
