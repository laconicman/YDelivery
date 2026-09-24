import SwiftUI

extension SettingsView {
    /// Pure presentation: plain values in, intents out (R1/R2). Previews are literals.
    struct Content: View {
        let isSignedIn: Bool
        let errorText: String?
        @Binding var draftToken: String
        @Binding var startCity: String
        /// The captured wire log's share URL — `nil` while nothing has been recorded.
        let diagnosticsURL: URL?
        let signIn: () -> Void
        let signOut: () -> Void

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
                        Button("Sign In", action: signIn)
                            .disabled(draftToken.isEmpty)
                    }
                } header: {
                    Text("Yandex Delivery account")
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
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
            }
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
        signIn: {},
        signOut: {}
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
        signIn: {},
        signOut: {}
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
        signIn: {},
        signOut: {}
    )
    .environment(StoreController(database: nil))
}
