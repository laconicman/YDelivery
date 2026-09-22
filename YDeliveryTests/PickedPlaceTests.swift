import Testing
@testable import YDelivery

@Suite("Picked place")
struct PickedPlaceTests {
    @Test("A street or landmark with no house number warns — the courier reads fullname")
    func noBuildingWarns() {
        #expect(PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, Красная площадь").lacksBuilding)
        #expect(PickedPlace(latitude: 55.75, longitude: 37.62, address: "Невский проспект").lacksBuilding)
    }

    @Test("A numbered building is the usual case — no warning")
    func numberedIsFine() {
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, Арбат, 10").lacksBuilding)
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "Каширское шоссе, 52").lacksBuilding)
    }

    @Test("A bare pin is honest by itself — the coordinates carry no warning")
    func barePinIsHonest() {
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "").lacksBuilding)
    }
}
