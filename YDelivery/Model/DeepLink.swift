import Foundation

/// The URLs the app answers to — the widget and Live Activity's only channel
/// into a running app (extensions can't share our controllers), and the App
/// Intents' hand-off for anything that opens a screen. One grammar, parsed in
/// one place, so a malformed or stale link degrades to "no link" instead of
/// halfway-opening something.
///
///   ydelivery://order/<uuid>            — that order's detail row
///   ydelivery://compose                 — a fresh draft
///   ydelivery://repeat?order=<uuid>     — a draft repeating that order's route
///   ydelivery://repeat?place=<uuid>     — a draft delivering to that saved place
///
/// `host` carries the verb because the scheme is ours alone — there is no
/// path-style ambiguity to defend against.
nonisolated enum DeepLink: Equatable {
    case order(UUID)
    case compose
    case repeatOrder(UUID)
    case repeatPlace(UUID)

    static let scheme = "ydelivery"

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "order":
            guard let id = url.pathComponents.dropFirst().first
                    .flatMap(UUID.init(uuidString:)) else { return nil }
            self = .order(id)
        case "compose":
            self = .compose
        case "repeat":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
            if let id = query.first(where: { $0.name == "order" })?.value
                .flatMap(UUID.init(uuidString:)) {
                self = .repeatOrder(id)
            } else if let id = query.first(where: { $0.name == "place" })?.value
                .flatMap(UUID.init(uuidString:)) {
                self = .repeatPlace(id)
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    /// The link a widget writes — `Link`/`widgetURL` targets, not user-facing.
    static func order(_ id: UUID) -> URL {
        URL(string: "\(scheme)://order/\(id.uuidString)")!
    }

    static func repeatOrder(_ id: UUID) -> URL {
        URL(string: "\(scheme)://repeat?order=\(id.uuidString)")!
    }

    static func repeatPlace(_ id: UUID) -> URL {
        URL(string: "\(scheme)://repeat?place=\(id.uuidString)")!
    }
}
