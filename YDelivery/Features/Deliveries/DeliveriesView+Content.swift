import SFSafeSymbols
import SwiftUI

extension DeliveriesView {
    /// Pure presentation: two genuinely different empty states, so the branch is structure
    /// rather than show/hide of the same view (R9), and the screen's one standing action —
    /// the prominent compose button (Design → "The tab bar goes"). Composing stays
    /// available signed-out: a route can be drafted before a token exists; only pricing
    /// and ordering will need the session.
    struct Content: View {
        let isSignedIn: Bool
        let compose: () -> Void

        var body: some View {
            Group {
                if isSignedIn {
                    ContentUnavailableView {
                        Label("No deliveries yet", systemSymbol: .shippingbox)
                    } description: {
                        Text("Orders you create will appear here, and stay here.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("Sign in to start", systemSymbol: .key)
                    } description: {
                        Text("Add your Yandex Delivery OAuth token in Settings.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: compose) {
                    Label("New Delivery", systemSymbol: .plus)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
}

#Preview("Signed in") {
    DeliveriesView.Content(isSignedIn: true, compose: {})
}

#Preview("Signed out") {
    DeliveriesView.Content(isSignedIn: false, compose: {})
}
