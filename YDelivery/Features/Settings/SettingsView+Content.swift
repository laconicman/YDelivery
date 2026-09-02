import SwiftUI

extension SettingsView {
    /// Pure presentation: plain values in, intents out (R1/R2). Previews are literals.
    struct Content: View {
        let isSignedIn: Bool
        let errorText: String?
        @Binding var draftToken: String
        @Binding var startCity: String
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
                } header: {
                    Text("New delivery")
                } footer: {
                    Text("Where an empty map starts when your location is unavailable.")
                }
            }
        }
    }
}

#Preview("Signed out") {
    @Previewable @State var token = ""
    @Previewable @State var city = ""
    SettingsView.Content(
        isSignedIn: false,
        errorText: nil,
        draftToken: $token,
        startCity: $city,
        signIn: {},
        signOut: {}
    )
}

#Preview("Signed in") {
    @Previewable @State var token = ""
    @Previewable @State var city = "Санкт-Петербург"
    SettingsView.Content(
        isSignedIn: true,
        errorText: nil,
        draftToken: $token,
        startCity: $city,
        signIn: {},
        signOut: {}
    )
}

#Preview("Failed sign-in") {
    @Previewable @State var token = "not-a-token"
    @Previewable @State var city = ""
    SettingsView.Content(
        isSignedIn: false,
        errorText: "The token could not be saved to the Keychain.",
        draftToken: $token,
        startCity: $city,
        signIn: {},
        signOut: {}
    )
}
