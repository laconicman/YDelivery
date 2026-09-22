import Testing
@testable import YDelivery

// Deliberately not @MainActor: PhoneFormat is nonisolated, and this suite running
// off the main actor is the proof (review, PR #26).
@Suite("Phone format")
struct PhoneFormatTests {
    @Test("A formatted number normalizes to E.164 — nothing to mis-copy on the wire")
    func normalizesToE164() {
        #expect(PhoneFormat.dialable("+7 912 345-67-89") == "+79123456789")
        #expect(PhoneFormat.dialable("+7 (495) 123-45-67") == "+74951234567")
    }

    @Test("What does not amount to a number is not pretended to be one")
    func refusesNonNumbers() {
        #expect(PhoneFormat.dialable("call after six") == nil)
        #expect(PhoneFormat.dialable("") == nil)
    }

    @Test("Saving normalizes the phone and touches nothing else")
    func saveNormalizesPhoneOnly() {
        let saved = Contact(
            givenName: "Иван",
            familyName: "Петров",
            phone: "+7 912 345-67-89",
            phoneExtension: "4152"
        ).withDialablePhone()
        #expect(saved.phone == "+79123456789")
        #expect(saved.givenName == "Иван")
        #expect(saved.phoneExtension == "4152")
    }

    @Test("An unparseable phone is kept verbatim — the blockers say the rest")
    func keepsUnparseableVerbatim() {
        let saved = Contact(givenName: "Анна", phone: "домофон 12").withDialablePhone()
        #expect(saved.phone == "домофон 12")
    }

    @Test("Storing normalizes — no path keeps a formatted number for the wire")
    func storableNormalizes() {
        // The claim schema's phone pattern accepts only E.164, so `storable` — the
        // single gate every save path reads — normalizes itself (review, PR #29:
        // Describe's exits bypassed `withDialablePhone` when the rule lived only
        // in the picker).
        let stored = Contact(givenName: "Иван", phone: "+7 912 345-67-89").storable
        #expect(stored?.phone == "+79123456789")
        let unparseable = Contact(givenName: "Анна", phone: "домофон 12").storable
        #expect(unparseable?.phone == "домофон 12", "verbatim, for the blockers to name")
    }
}
