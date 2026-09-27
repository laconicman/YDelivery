import PhotosUI
import SFSafeSymbols
import SwiftUI
import UIKit
import YDeliveryKit

extension OrderChatView {
    /// Pure presentation: the stream as read, the composer as intent. States are
    /// distinct branches — asking (nil), refused (error), empty, populated (R9).
    struct Content: View {
        let messages: [OrderMessage]?
        /// Photo payloads the model has fetched, by attachment id.
        let photoData: [UUID: Data]
        let loadError: String?
        let sendError: String?
        let isSending: Bool
        @Binding var composer: String
        let send: () -> Void
        let confirmReceipt: () -> Void
        let sendPhoto: (Data) -> Void
        /// Asks the model to fetch a payload — idempotent per attachment.
        let photo: (UUID) -> Void

        /// The pending picker selection — the photo post's raw material.
        @State private var pickedItem: PhotosPickerItem?

        var body: some View {
            List {
                if let loadError {
                    Section {
                        Label(loadError, systemSymbol: .exclamationmarkTriangle)
                            .foregroundStyle(.secondary)
                    }
                }
                if let messages {
                    if messages.isEmpty {
                        Text("No messages yet — this is the order's shared stream.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(messages, content: row)
                    }
                } else if loadError == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) { composerBar }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: confirmReceipt) {
                        Label("Mark received", systemSymbol: .checkmarkCircle)
                    }
                    .disabled(isSending)
                }
            }
            .onChange(of: pickedItem) { _, item in
                pickedItem = nil
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        sendPhoto(data)
                    }
                }
            }
        }

        /// Text field and the photo picker's door — the two append shapes the
        /// stream accepts.
        private var composerBar: some View {
            HStack(spacing: Layout.Spacing.gutter) {
                PhotosPicker(
                    selection: $pickedItem, matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemSymbol: .photo)
                }
                .disabled(isSending)
                TextField("Message", text: $composer, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemSymbol: isSending ? .ellipsisCircle : .arrowUpCircleFill)
                }
                .disabled(isSending || composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Layout.Spacing.edge)
            .background(.bar)
            .overlay(alignment: .top) {
                if let sendError {
                    Text(sendError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .offset(y: -Layout.Spacing.edge)
                }
            }
        }

        /// One stream row, shaped by kind — text and photos are bubbles,
        /// structured kinds render as the human events they are («Ирина
        /// подтвердила получение»), and a kind this build doesn't know still
        /// shows its text rather than vanishing.
        @ViewBuilder
        private func row(for message: OrderMessage) -> some View {
            switch message.kind {
            case OrderMessage.Kind.photo:
                photoRow(message)
            case OrderMessage.Kind.receptionConfirmed:
                eventRow(message, verb: "confirmed receipt")
            default:
                if let text = message.text, !text.isEmpty {
                    textRow(message, text: text)
                } else {
                    // A future kind with no text still leaves a legible trace.
                    eventRow(message, verb: "posted (\(message.kind))")
                }
            }
        }

        private func textRow(_ message: OrderMessage, text: String) -> some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                meta(message)
                Text(text)
            }
            .listRowSeparator(.hidden)
        }

        private func photoRow(_ message: OrderMessage) -> some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.unit) {
                meta(message)
                if let ref = message.attachmentRef {
                    if let data = photoData[ref], let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.card))
                    } else {
                        // The payload may still be syncing — the frame asks for
                        // it once and stays a placeholder until it lands.
                        ContentUnavailableView {
                            Label("Photo", systemSymbol: .photo)
                        }
                        .frame(height: Self.photoPlaceholderHeight)
                        .onAppear { photo(ref) }
                    }
                }
                if let text = message.text, !text.isEmpty {
                    Text(text).font(.subheadline)
                }
            }
            .listRowSeparator(.hidden)
        }

        /// A structured kind as a sentence — human events sit beside provider
        /// truth, never in its clothes (doc:Schema).
        private func eventRow(_ message: OrderMessage, verb: String) -> some View {
            HStack(spacing: Layout.Spacing.tight) {
                Image(systemSymbol: .checkmarkBubble)
                Text("\(author(of: message)) \(verb)")
                    .italic()
                Spacer()
                Text(message.sentAt, format: .dateTime.hour().minute())
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
        }

        /// The byline — only when the post carried a hint; a local post of your
        /// own doesn't name you to yourself.
        private func meta(_ message: OrderMessage) -> some View {
            HStack(spacing: Layout.Spacing.tight) {
                if let author = message.authorHint {
                    Text(author).font(.footnote).bold()
                }
                Spacer()
                Text(message.sentAt, format: .dateTime.hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private func author(of message: OrderMessage) -> String {
            message.authorHint ?? String(localized: "A participant")
        }

        private static let photoPlaceholderHeight: CGFloat = 120
    }
}
