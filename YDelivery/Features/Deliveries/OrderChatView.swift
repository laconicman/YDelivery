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
    /// text so retrying is not a retype (SettingsView's own rule).
    private func sendText() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            let sent = await model.post(
                OrderMessage(
                    orderID: order.id, kind: OrderMessage.Kind.text, text: text),
                using: store.postMessage,
                then: { try await store.messages(for: order.id) })
            if sent { composer = "" }
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

    private func sendPhoto(_ data: Data) {
        Task {
            _ = await model.postPhoto(
                orderID: order.id, data: data,
                using: store.postPhotoMessage,
                then: { try await store.messages(for: order.id) })
        }
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
        /// A photo fetch already asked for — rows re-ask on every render, and
        /// the fetch itself is what must not repeat.
        private var photoRequests: Set<UUID> = []

        func load(using fetch: @escaping () async throws -> [OrderMessage]) async {
            loading?.cancel()
            loading = Task {
                defer { loading = nil }
                do {
                    messages = try await fetch()
                    loadError = nil
                } catch {
                    loadError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            await loading?.value
        }

        /// Posts one entry and re-reads the stream — the read is local and
        /// cheap, and it is how the posted row arrives in its sorted seat.
        /// Returns whether the post landed; the caller consumes its draft then.
        func post(
            _ message: OrderMessage,
            using post: (OrderMessage) async throws -> Void,
            then reload: () async throws -> [OrderMessage]
        ) async -> Bool {
            guard !isSending else { return false }
            isSending = true
            defer { isSending = false }
            do {
                try await post(message)
                messages = try await reload()
                sendError = nil
                return true
            } catch {
                sendError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                return false
            }
        }

        func postPhoto(
            orderID: Order.ID, data: Data,
            using post: (Order.ID, Data, String?) async throws -> Void,
            then reload: () async throws -> [OrderMessage]
        ) async -> Bool {
            guard !isSending else { return false }
            isSending = true
            defer { isSending = false }
            do {
                try await post(orderID, data, nil)
                messages = try await reload()
                sendError = nil
                return true
            } catch {
                sendError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                return false
            }
        }

        /// A photo's bytes, asked once per attachment — a nil answer (payload
        /// still syncing) leaves the frame a placeholder, not a retry loop:
        /// the next `.refreshable` pull re-asks by way of a fresh render.
        func photo(_ id: UUID, using fetch: @escaping (UUID) async throws -> Data?) {
            guard photoData[id] == nil, !photoRequests.contains(id) else { return }
            photoRequests.insert(id)
            Task {
                defer { photoRequests.remove(id) }
                if let data = try? await fetch(id) {
                    photoData[id] = data
                }
            }
        }
    }
}

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
    NavigationStack {
        OrderChatView(order: .previewDone)
            .environment(StoreController(database: nil))
    }
}
