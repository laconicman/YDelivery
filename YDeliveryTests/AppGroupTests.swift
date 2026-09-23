import Foundation
import Testing
@testable import YDelivery
import YDeliveryKit

@Suite("App Group")
struct AppGroupTests {
    /// Runs hosted in the app, so it exercises the entitled process — the same resolution
    /// a widget target will perform. The simulator is lenient about unentitled groups, so
    /// the strict proof is a device run; this still pins the production path
    /// (`AppDatabase.inAppGroup(id:)`) and the one group ID both sides must agree on.
    @Test("The store's container resolves inside the entitled app")
    func containerResolves() {
        #expect(AppDatabase.inAppGroup(id: AppGroup.id) != nil)
    }
}
