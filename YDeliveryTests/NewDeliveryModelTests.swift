import Testing
@testable import YDelivery

@Suite("New delivery draft")
@MainActor
struct NewDeliveryModelTests {
    private let office = PickedPlace(latitude: 55.7558, longitude: 37.6173, address: "Офис")
    private let home = PickedPlace(latitude: 55.6460, longitude: 37.6681, address: "Дом")

    @Test("The route completes only when both ends are set")
    func routeCompleteness() {
        let model = NewDeliveryView.Model()
        #expect(!model.isRouteComplete)

        model[.pickup] = office
        #expect(!model.isRouteComplete)

        model[.dropoff] = home
        #expect(model.isRouteComplete)
    }

    @Test("Swapping exchanges the ends, and is only offered when it exchanges")
    func swapExchanges() {
        let model = NewDeliveryView.Model()
        model.pickup = office
        #expect(!model.canSwap, "with one end empty a swap would read as data loss")

        model.dropoff = home
        #expect(model.canSwap)

        model.swapEnds()
        #expect(model.pickup == home)
        #expect(model.dropoff == office)
    }

    @Test("The subscript reads and writes the end it names")
    func subscriptRoutesToEnds() {
        let model = NewDeliveryView.Model()
        model[.dropoff] = home

        #expect(model.pickup == nil)
        #expect(model.dropoff == home)
        #expect(model[.dropoff] == home)
    }
}
