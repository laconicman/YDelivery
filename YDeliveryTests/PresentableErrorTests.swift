import Foundation
import Testing
@testable import YDelivery

/// The share alert's error half — a refusal lands in the model as the error
/// itself (issue #70), so the alert can read title, reason, and remedy off it.
@Suite("A presented error")
@MainActor
struct PresentableErrorTests {
    private struct FilledError: LocalizedError {
        var errorDescription: String? { "Sharing needs iCloud sync." }
        var failureReason: String? { "This install could not start it." }
        var recoverySuggestion: String? { "Try again once sync is running." }
    }

    private struct BareError: Error {}

    @Test("A filled LocalizedError keeps its own words")
    func localizedErrorForwardsFields() {
        let presented = PresentableError(FilledError())
        #expect(presented.errorDescription == "Sharing needs iCloud sync.")
        #expect(presented.message ==
                "This install could not start it.\n\nTry again once sync is running.")
    }

    @Test("A bare error still says something — its localized words")
    func bareErrorKeepsLocalizedWords() {
        let presented = PresentableError(CocoaError(.coderInvalidValue))
        #expect(presented.errorDescription == CocoaError(.coderInvalidValue).localizedDescription)
    }

    @Test("A refused share presents the error, not a sheet")
    func shareRefusalIsPresentable() async {
        let model = OrderDetailView.Model()
        let task = model.share(UUID(), title: "T") { _, _ in
            throw BareError()
        }
        await task?.value
        #expect(model.shareError != nil)
        #expect(model.sharedRecord == nil)
    }
}
