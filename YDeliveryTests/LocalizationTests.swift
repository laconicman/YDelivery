import Foundation
import Testing

@Suite("The app string catalog")
struct LocalizationTests {
    /// A bundle pinned to Russian: `Bundle(path: xx.lproj)` resolves that
    /// language's table regardless of the test host's locale.
    private func ru(_ key: String) -> String? {
        guard let lproj = Bundle.main.path(forResource: "ru", ofType: "lproj"),
              let ru = Bundle(path: lproj) else { return nil }
        return ru.localizedString(forKey: key, value: nil, table: nil)
    }

    /// The ru table's compiled stringsdict — the plural specs verbatim.
    /// (The substitution picker is process-locale-bound, so few/many are
    /// asserted structurally here and rendered on a Russian device.)
    private func ruDict(_ key: String) throws -> [String: Any] {
        let lproj = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let dict = try #require(NSDictionary(contentsOfFile:
            lproj + "/Localizable.stringsdict") as? [String: Any])
        return try #require(dict[key] as? [String: Any])
    }

    @Test("Russian resolves for representative keys")
    func russianResolves() {
        #expect(ru("New delivery") == "Новая доставка")
        #expect(ru("Cancel this delivery — pay %@") == "Отменить доставку — %@")
        #expect(ru("Who receives") == "Кто принимает")
        #expect(ru("«%@» is required — the order doesn't leave without it.")
                == "«%@» обязательно — без него заказ не уйдёт.")
    }

    @Test("Provider vocabulary is kept in Russian")
    func providerVocabulary() {
        #expect(ru("Claim document") == "Документ заявки")
        #expect(ru("Sent once per claim — the accompanying document on the paperwork.")?
            .contains("заявк") == true)
        #expect(ru("to the door") == "до двери")
        #expect(ru("To the door") == "До двери")
    }

    @Test("Russian count forms compile to plural specs")
    func russianPluralSpecs() throws {
        let loaders = try ruDict("%lld loaders")
        #expect(loaders["value"] as? [String: Any] != nil)
        let forms = try #require(loaders["value"] as? [String: Any])
        #expect(forms["one"] as? String == "%lld грузчик")
        #expect(forms["few"] as? String == "%lld грузчика")
        #expect(forms["many"] as? String == "%lld грузчиков")

        let days = try ruDict("From an hour ahead, up to %lld days out.")
        let dayForms = try #require(days["value"] as? [String: Any])
        #expect(dayForms["few"] as? String == "От часа вперёд и до %lld дня.")
        #expect(dayForms["many"] as? String == "От часа вперёд и до %lld дней.")

        let combined = try ruDict(
            "^[%1$lld item](inflect: true) leave here · ^[%2$lld item](inflect: true) arrive here")
        #expect(combined["NSStringLocalizedFormatKey"] as? String
                == "%1$#@leaving@ отсюда · %2$#@arriving@ сюда")
        let leaving = try #require(combined["leaving"] as? [String: Any])
        #expect(leaving["one"] as? String == "%1$lld предмет уезжает")
        #expect(leaving["many"] as? String == "%1$lld предметов уезжают")
    }

    @Test("The singular category renders through the substitution")
    func singularRenders() {
        let fmt = ru("%lld loaders")
        #expect(fmt != nil)
        // "one" is reachable in any process locale; few/many need a ru host.
        #expect(fmt.map { String.localizedStringWithFormat($0, 1) } == "1 грузчик")
    }

    @Test("Unindexed interpolation keys resolve — String(localized:) looks those up")
    func unindexedAliases() {
        // `Text` looks keys up indexed (`%1$@`); `String(localized:)` looks them up
        // unindexed (`%@`). The catalog carries both, or direct strings stay English.
        #expect(ru("Order %@ · %@") == "Заказ %1$@ · %2$@")
        #expect(ru("%@ · ~%@") == "%1$@ · ~%2$@")
        #expect(ru("%@, ext. %@") == "%1$@, доб. %2$@")
        #expect(ru("Fits %@: up to %@.") == "Влезает в %1$@: до %2$@.")
        #expect(ru("Doesn't fit %@ — its bound is %@. Pick a larger class, or it may be refused at the door.")
                == "Не влезает в %1$@ — предел %2$@. Выберите класс побольше, иначе могут отказать у двери.")
    }

    @Test("The provider's extra classes have sender words")
    func extraClassesResolve() {
        #expect(ru("Same-day") == "День в день")
        #expect(ru("Super-express") == "Быстрее")
        #expect(ru("Signed in") == "Вход выполнен")
    }

    @Test("English falls back to the key")
    func englishFallback() {
        #expect(Bundle.main.localizedString(forKey: "New delivery",
                                            value: nil, table: nil) == "New delivery")
    }
}
