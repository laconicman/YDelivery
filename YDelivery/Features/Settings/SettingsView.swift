import SwiftUI

/// Root view of the Settings screen: maps the content's intents onto the session
/// controller (R6 — the content stays a pipe; the decisions live in the controller).
struct SettingsView: View {
    @Environment(ClientController.self) private var session
    @State private var draftToken = ""
    /// The picker's fallback start when location is unavailable (Roadmap → Phase 2).
    /// A plain preference, not a secret — `@AppStorage` is the right shelf.
    @AppStorage("startCity") private var startCity = ""

    var body: some View {
        NavigationStack {
            Content(
                isSignedIn: session.isSignedIn,
                errorText: session.signInErrorText,
                draftToken: $draftToken,
                startCity: $startCity,
                signIn: {
                    session.signIn(token: draftToken)
                    // Only a successful sign-in consumes the draft: a failure keeps the
                    // typed token in the field so retrying is not a full retype.
                    if session.isSignedIn { draftToken = "" }
                },
                signOut: { session.signOut() }
            )
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
}
