import CloudKit
import OSLog
import UIKit

/// The share-acceptance handoff (doc:Collaboration): UIKit instantiates both
/// delegates, so the database reaches them through a property the composition
/// root fills, not an initializer that never runs.
final class YDeliveryAppDelegate: UIResponder, UIApplicationDelegate {
    /// Composition-injected — `AppDatabase.acceptShare` with the optional lifted:
    /// a store that never resolved throws rather than pretending an acceptance.
    var acceptShare: ((CKShare.Metadata) async throws -> Void)?

    /// Names the scene delegate class — the generated scene manifest makes the
    /// app scene-based, so UIKit consults this for every scene connection and
    /// share URLs reach `YDeliverySceneDelegate`.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role)
        configuration.delegateClass = YDeliverySceneDelegate.self
        return configuration
    }
}

/// Scene-side delivery of the same event in both temperatures: a tapped share
/// URL cold-launches with the metadata in `connectionOptions`; a warm accept
/// arrives through `userDidAcceptCloudKitShareWith`.
final class YDeliverySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        accept(cloudKitShareMetadata)
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    /// Back through the app delegate for the injected closure — the scene
    /// delegate can receive no init-time dependencies. The task is owned by
    /// the acceptance itself: a failure is logged, and the sender can tap the
    /// link again — a retried accept is the system's own recovery, not a
    /// spinner we must keep alive.
    private func accept(_ metadata: CKShare.Metadata) {
        guard let acceptShare = (UIApplication.shared.delegate as? YDeliveryAppDelegate)?.acceptShare
        else {
            // The composition root fills the property before any scene
            // connects — reaching here means an acceptance with nobody to
            // hand it to, which is worth a log line, not silence.
            Self.logger.error("Share acceptance arrived with no acceptShare installed")
            return
        }
        Task {
            do {
                try await acceptShare(metadata)
            } catch {
                Self.logger.error(
                    "CloudKit share acceptance failed: \(error.localizedDescription)")
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "sharing")
}
