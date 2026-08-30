import Foundation
import Testing
import YDeliveryKit

@Suite("App Group")
struct AppGroupTests {
    /// Runs hosted in the app, so it exercises the entitled process — the same resolution
    /// a widget target will perform. The simulator is lenient about unentitled groups, so
    /// the strict proof is a device run; this still pins the production path
    /// (`OrderStore.inAppGroup()`) and the one group ID both sides must agree on.
    @Test("The store's container resolves inside the entitled app")
    func containerResolves() {
        #expect(OrderStore.inAppGroup() != nil)
    }
}
