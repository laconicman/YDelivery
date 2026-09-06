import Foundation

/// One home for the box-dimensions line — «25 × 18 × 15 cm» — so the separator and the
/// unit are knowledge written once, not string literals scattered per call site
/// (author's standing preference: no magic strings). Display formatting lives in the
/// model layer's extensions, never in a view body (R5).
nonisolated enum Dimensions {
    /// The multiplication sign with its breathing room — the join every dimensions line
    /// uses.
    static let separator = " × "

    /// «25 × 18 × 15 cm», localized numbers included.
    static func centimeters(_ values: [Double]) -> String {
        String(localized: "\(text(values)) cm")
    }

    /// The bare joined run — for lines that carry their own unit wording.
    static func text(_ values: [Double]) -> String {
        values
            .map { $0.formatted(.number.precision(.fractionLength(0...1))) }
            .joined(separator: separator)
    }
}
