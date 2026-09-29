import Foundation

/// An `Error` kept whole for `.alert(isPresented:error:actions:message:)` — the
/// overload reads `errorDescription` for the alert's title and hands the value
/// to `message:` for its body. Seam errors arrive already filled (a properly
/// filled error is displayed as is — the author's rule), so a `LocalizedError`
/// forwards its own fields; a bare `NSError`/`CKError` keeps its localized
/// words as the title instead of being flattened into one pre-joined string.
nonisolated struct PresentableError: LocalizedError {
    let underlying: any Error

    init(_ error: any Error) { underlying = error }

    var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription
            ?? underlying.localizedDescription
    }
    var failureReason: String? { (underlying as? LocalizedError)?.failureReason }
    var recoverySuggestion: String? { (underlying as? LocalizedError)?.recoverySuggestion }

    /// The alert's body — reason first, then remedy, the same order the overload
    /// itself composes for a `LocalizedError` it already knows.
    var message: String {
        [failureReason, recoverySuggestion]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
