import SwiftUI

extension DeliveriesView {
    /// Pure presentation: two genuinely different empty states, so the branch is structure
    /// rather than show/hide of the same view (R9).
    struct Content: View {
        let isSignedIn: Bool

        var body: some View {
            if isSignedIn {
                ContentUnavailableView(
                    "No deliveries yet",
                    systemImage: "shippingbox",
                    description: Text("Orders you create will appear here, and stay here.")
                )
            } else {
                ContentUnavailableView(
                    "Sign in to start",
                    systemImage: "key",
                    description: Text("Add your Yandex Delivery OAuth token in Settings.")
                )
            }
        }
    }
}

#Preview("Signed in") {
    DeliveriesView.Content(isSignedIn: true)
}

#Preview("Signed out") {
    DeliveriesView.Content(isSignedIn: false)
}
