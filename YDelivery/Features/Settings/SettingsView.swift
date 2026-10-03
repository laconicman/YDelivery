import SwiftUI
import UserNotifications

/// Root view of the Settings screen: maps the content's intents onto the session
/// controller (R6 — the content stays a pipe; the decisions live in the controller).
struct SettingsView: View {
    @Environment(ClientController.self) private var session
    @Environment(NotificationController.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var draftToken = ""
    /// The picker's fallback start when location is unavailable (Roadmap → Phase 2).
    /// A plain preference, not a secret — `@AppStorage` is the right shelf.
    @AppStorage("startCity") private var startCity = ""
    /// The system's last-read answer for notification permission — `nil` until the
    /// first read; re-read on each foregrounding so a trip to system Settings
    /// lands on the row.
    @State private var notificationStatus: UNAuthorizationStatus?

    /// «1.0 (1)» — marketing version and build, so a TestFlight row answers
    /// «which build is this».
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            Content(
                isSignedIn: session.isSignedIn,
                errorText: session.signInErrorText,
                draftToken: $draftToken,
                startCity: $startCity,
                diagnosticsURL: session.diagnosticsURL,
                notificationStatus: notificationStatus,
                appVersion: appVersion,
                signIn: {
                    Task {
                        await session.signIn(token: draftToken)
                        // Only a successful sign-in consumes the draft: a failure keeps the
                        // typed token in the field so retrying is not a full retype.
                        if session.isSignedIn { draftToken = "" }
                    }
                },
                signOut: { session.signOut() },
                requestNotifications: {
                    Task {
                        _ = await notifications.requestAuthorization()
                        notificationStatus = await notifications.authorizationStatus()
                    }
                },
                openSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            )
            .navigationTitle("Settings")
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                notificationStatus = await notifications.authorizationStatus()
            }
        }
    }
}

#Preview {
    let store = StoreController(database: nil)
    SettingsView()
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(NotificationController(store: store))
}
