import Foundation
import Testing
import YDeliveryKit

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

    /// The retrofit sweep: every key the code emits that the catalog lacked —
    /// indexed `Text` forms beside their unindexed `String(localized:)` twins,
    /// the toolbar's sort/filter words, the notification rows.
    @Test("The sweep's new keys resolve to Russian")
    func sweepKeysResolveRussian() throws {
        #expect(ru("Flat %1$@") == "Кв. %1$@")
        #expect(ru("stop %1$lld") == "точка %1$lld")
        #expect(ru("Newest first") == "Сначала новые")
        #expect(ru("Everything") == "Все")
        #expect(ru("Nothing to show") == "Нечего показать")
        #expect(ru("Review the order") == "Проверить заказ")
        #expect(ru("No route between these points.") == "Между этими точками нет маршрута.")
        #expect(ru("The provider refused the order.") == "Провайдер отказал в заказе.")
        #expect(ru("Nothing matches “%1$@”.") == "По запросу “%1$@” ничего нет.")
        #expect(ru("Clear search") == "Очистить поиск")
        // The single-arg inflect keys compile a plural spec like their
        // unindexed twins — `NSStringLocalizedFormatKey` names the substitution.
        let leave = try ruDict("^[%1$lld item](inflect: true) leave here")
        #expect(leave["NSStringLocalizedFormatKey"] as? String == "%#@value@")
        let forms = try #require(leave["value"] as? [String: Any])
        #expect(forms["one"] as? String == "%1$lld предмет уезжает отсюда")
        #expect(forms["many"] as? String == "%1$lld предметов уезжают отсюда")

        // #117's tariff keys resolve through the table now that the strip's
        // call sites are on this tree.
        #expect(ru("Fastest") == "Сначала быстрые")
        #expect(ru("Cheapest") == "Сначала дешёвые")
        #expect(ru("by %@") == "к %@")
        #expect(ru("pickup by %@") == "забор к %@")
        #expect(ru("Delivery options") == "Варианты доставки")
        #expect(ru("Prices refreshed — the quote expired")
                == "Цены обновлены — расчёт устарел")

        // The archive door's keys — the shelf's words and the still-moving refusal.
        #expect(ru("Archive") == "В архив")
        #expect(ru("Unarchive") == "Вернуть из архива")
        #expect(ru("Archived") == "Архив")
        #expect(ru("Nothing archived yet") == "В архиве пока пусто")
        #expect(ru("Finished deliveries you shelve wait here.")
                == "Убранные в архив завершённые доставки ждут здесь.")
        #expect(ru("This delivery is still moving — archive it when it has finished.")
                == "Эта доставка ещё в пути — уберите её в архив, когда она завершится.")
    }

    @Test("The provider's extra classes have sender words")
    func extraClassesResolve() {
        #expect(ru("Same-day") == "День в день")
        #expect(ru("Super-express") == "Быстрее")
        #expect(ru("Within the day") == "В течение дня")
        #expect(ru("Signed in") == "Вход выполнен")
    }

    @Test("English falls back to the key")
    func englishFallback() {
        #expect(Bundle.main.localizedString(forKey: "New delivery",
                                            value: nil, table: nil) == "New delivery")
    }

    /// The widgets' status words carry `bundle:` `.data`/`.kit`, not the
    /// widget's own table — so a `LocalizedStringResource` resolves in the
    /// kit's resource bundle, which ships `ru.lproj` into every target that
    /// links the package (verified: it sits inside `YDeliveryWidgets.appex`
    /// beside the appex's own). The same lookup the appex performs.
    @Test("Kit resources resolve Russian from the app's host")
    func kitResourcesResolveRussian() throws {
        var phrase = try #require(ProviderStatusPhrase.phrase(for: "delivery_arrived"))
        phrase.locale = Locale(identifier: "ru")
        #expect(String(localized: phrase) == "Курьер у двери получателя")

        var words = OrderStatus.active.words
        words.locale = Locale(identifier: "ru")
        #expect(String(localized: words) == "Курьер в пути")
    }
}
