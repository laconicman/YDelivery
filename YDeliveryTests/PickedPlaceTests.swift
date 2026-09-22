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
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, Тверская улица, 12к2").lacksBuilding)
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, Пятницкая улица, 3/1").lacksBuilding)
    }

    @Test("Street-name digits are not a house — the last word alone may be one")
    func streetDigitsStillWarn() {
        // Review, PR #30: «улица 8 Марта» is a street, not a building; a leading
        // postal code proves nothing either.
        #expect(PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, улица 8 Марта").lacksBuilding)
        #expect(PickedPlace(latitude: 55.75, longitude: 37.62, address: "123456, Москва, улица 8 Марта").lacksBuilding)
        #expect(PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, проспект 60-летия Октября").lacksBuilding)
        // …and the same street *with* its house stays silent.
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, улица 8 Марта, 12").lacksBuilding)
    }

    @Test("Directions after the number don't unname the house — the string is editable")
    func trailingDetailsKeepTheHouse() {
        // Review, PR #30: the sender may append landmarks after the building number.
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, Арбат, 10, вход со двора").lacksBuilding)
        // …while directions alone still can't fake one.
        #expect(PickedPlace(latitude: 55.75, longitude: 37.62, address: "Москва, Красная площадь, вход со двора").lacksBuilding)
    }

    @Test("A bare pin is honest by itself — the coordinates carry no warning")
    func barePinIsHonest() {
        #expect(!PickedPlace(latitude: 55.75, longitude: 37.62, address: "").lacksBuilding)
    }
}
