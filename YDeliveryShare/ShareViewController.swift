import SwiftUI
import UIKit
import YDeliveryKit

/// The extension's host: a SwiftUI sheet inside the share-services point.
/// «В доставку» writes the `SharedDraft` file and tries to open the app on
/// it; when the system declines to open (share extensions' `open` is best-
/// effort), the file still waits and the app applies it on next activation —
/// the share is never lost.
final class ShareViewController: UIViewController {
    private let model = ShareModel()
    /// The attachment read + geocode — owned so a cancelled share stops it
    /// rather than letting it finish into a dead context (rule 6).
    private var ingest: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(
            model: model,
            cancel: { [weak self] in
                self?.ingest?.cancel()
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            },
            confirm: { [weak self] in self?.handOff() }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        ingest = Task { await model.load(context: extensionContext) }
    }

    private func handOff() {
        guard let context = extensionContext else { return }
        ingest?.cancel()
        do {
            if let draft = model.sharedDraft() {
                try SharedDraftStore.write(draft, inAppGroup: ShareIdentity.appGroupID)
            }
        } catch {
            context.cancelRequest(withError: error)
            return
        }
        // `NSExtensionContext` predates Sendable — the open completion is
        // @Sendable, and the SDK object crosses it as it always has.
        nonisolated(unsafe) let extensionContext = context
        extensionContext.open(ShareIdentity.sharedDraftURL) { _ in
            extensionContext.completeRequest(returningItems: nil)
        }
    }
}
