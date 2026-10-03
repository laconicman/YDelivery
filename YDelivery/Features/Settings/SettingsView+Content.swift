import SwiftUI
import UserNotifications
import YDeliveryKit

extension SettingsView {
    /// Pure presentation: plain values in, intents out (R1/R2). Previews are literals.
    struct Content: View {
        let isSignedIn: Bool
        let errorText: String?
        @Binding var draftToken: String
        @Binding var startCity: String
        /// The captured wire log's share URL — `nil` while nothing has been recorded.
        let diagnosticsURL: URL?
        /// The system's answer to the notification permission — `nil` until the
        /// root's first read lands.
        let notificationStatus: UNAuthorizationStatus?
        /// «1.0 (1)» — marketing version and build, derived at the root (R5).
        let appVersion: String
        let signIn: () -> Void
        let signOut: () -> Void
        /// The «Turn on» row's intent — the controller shares the lazy prompt's
        /// single flight.
        let requestNotifications: () -> Void
        /// The «Open Settings» row's intent for a permission already answered.
        let openSettings: () -> Void

        /// The business cabinet — Интеграции → «Получить токен» is where the
        /// vendor issues the long-lived OAuth token this form asks for.
        private static let tokenVendorURL = URL(string: "https://dostavka.yandex.ru/personal-account/")!

        var body: some View {
            Form {
                Section {
                    if isSignedIn {
                        LabeledContent("Status", value: "Signed in")
                        Button("Sign Out", role: .destructive, action: signOut)
                    } else {
                        SecureField("OAuth token", text: $draftToken)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Link("Get a token — dostavka.yandex.ru", destination: Self.tokenVendorURL)
                        Button("Sign In", action: signIn)
                            .disabled(draftToken.isEmpty)
                    }
                } header: {
                    Text("Yandex Delivery account")
                } footer: {
                    if let errorText {
                        Notice(.error, errorText)
                    } else if !isSignedIn {
                        Text("The long-lived OAuth token from your Yandex Delivery profile. Stored in the Keychain, on this device only.")
                    }
                }

                Section {
                    TextField("Start city", text: $startCity)
                        .textContentType(.addressCity)
                    // «Ваши поля» — the draft's extra fields are organization-level
                    // settings, not per-order chores (board `4b`).
                    NavigationLink("Your fields", destination: CustomFieldsView())
                } header: {
                    Text("New delivery")
                } footer: {
                    Text("Where an empty map starts when your location is unavailable.")
                }

                Section {
                    LabeledContent("Status", value: notificationStatus?.words ?? "…")
                    switch notificationStatus {
                    case .notDetermined:
                        Button("Turn On Notifications", action: requestNotifications)
                    case .denied:
                        Button("Open Notification Settings", action: openSettings)
                    case .authorized, .provisional, .ephemeral, .none:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Status changes post local notifications when the app syncs — foreground or background refresh — the best-effort bridge until real push exists.")
                }

                Section {
                    if let diagnosticsURL {
                        ShareLink("Share diagnostics log", item: diagnosticsURL)
                    } else {
                        Text("Nothing captured yet")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Requests and responses the app exchanged are kept on this device — route addresses, names, phone numbers. Share the log to help pin down what the API actually answered.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension UNAuthorizationStatus {
    /// The row's plain words for the system's answer — «Not asked yet», not a
    /// state machine dump.
    var words: String {
        switch self {
        case .notDetermined: "Not asked yet"
        case .denied: "Off"
        case .authorized, .provisional, .ephemeral: "On"
        @unknown default: "—"
        }
    }
}

// «Your fields» reads the environment — every preview carries a store so
// navigating there from a preview works (review, PR #42).
#Preview("Signed out") {
    @Previewable @State var token = ""
    @Previewable @State var city = ""
    SettingsView.Content(
        isSignedIn: false,
        errorText: nil,
        draftToken: $token,
        startCity: $city,
        diagnosticsURL: nil,
        notificationStatus: .notDetermined,
        appVersion: "1.0 (1)",
        signIn: {},
        signOut: {},
        requestNotifications: {},
        openSettings: {}
    )
    .environment(StoreController(database: nil))
}

#Preview("Signed in") {
    @Previewable @State var token = ""
    @Previewable @State var city = "Санкт-Петербург"
    SettingsView.Content(
        isSignedIn: true,
        errorText: nil,
        draftToken: $token,
        startCity: $city,
        diagnosticsURL: nil,
        notificationStatus: .authorized,
        appVersion: "1.0 (1)",
        signIn: {},
        signOut: {},
        requestNotifications: {},
        openSettings: {}
    )
    .environment(StoreController(database: nil))
}

#Preview("Notifications denied") {
    @Previewable @State var token = ""
    @Previewable @State var city = ""
    SettingsView.Content(
        isSignedIn: true,
        errorText: nil,
        draftToken: $token,
        startCity: $city,
        diagnosticsURL: nil,
        notificationStatus: .denied,
        appVersion: "1.0 (1)",
        signIn: {},
        signOut: {},
        requestNotifications: {},
        openSettings: {}
    )
    .environment(StoreController(database: nil))
}

#Preview("Failed sign-in") {
    @Previewable @State var token = "not-a-token"
    @Previewable @State var city = ""
    SettingsView.Content(
        isSignedIn: false,
        errorText: "The token could not be saved to the Keychain.",
        draftToken: $token,
        startCity: $city,
        diagnosticsURL: nil,
        notificationStatus: .notDetermined,
        appVersion: "1.0 (1)",
        signIn: {},
        signOut: {},
        requestNotifications: {},
        openSettings: {}
    )
    .environment(StoreController(database: nil))
}
