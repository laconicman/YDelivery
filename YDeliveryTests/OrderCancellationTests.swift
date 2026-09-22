import Foundation
import Testing
import YandexDeliveryExpressAPI
import YDeliveryKit
@testable import YDelivery

/// The cancellation slice — terms decoded at the boundary, the gate on Order, and the
/// detail model's ask → confirm → done machine. Wire shapes are constructed here, the
/// one place generated types may appear beside app models (CLAUDE.md rule 1).
@Suite("Cancelling a claim")
@MainActor
struct OrderCancellationTests {
    private func termsOutput(
        _ state: Components.Schemas.CancelInfoCancelState,
        priceWithVat: String? = nil,
        price: String? = nil,
        currency: Components.Schemas.Currency? = nil
    ) -> Operations.GetClaimCancelInfo.Output {
        .ok(.init(body: .json(.init(
            cancelState: state,
            currency: currency,
            price: price,
            priceWithVat: priceWithVat
        ))))
    }

    @Test("Free terms stay free")
    func freeTerms() throws {
        #expect(try ClientController.cancelTerms(from: termsOutput(.free)) == .free)
    }

    @Test("Paid terms keep the with-VAT figure — the number this app quotes everywhere")
    func paidTermsKeepWithVat() throws {
        let terms = try ClientController.cancelTerms(from: termsOutput(
            .paid, priceWithVat: "807.60", price: "800", currency: .rub
        ))
        guard case .paid(let price, let currency) = terms else {
            Issue.record("expected paid terms, got \(terms)")
            return
        }
        #expect(price == Decimal(string: "807.6", locale: Locale(identifier: "en_US_POSIX")))
        #expect(currency == "RUB")
    }

    @Test("A paid answer with no price stays paid, unnamed rather than invented")
    func paidWithoutPrice() throws {
        let terms = try ClientController.cancelTerms(from: termsOutput(.paid))
        guard case .paid(let price, _) = terms else {
            Issue.record("expected paid terms, got \(terms)")
            return
        }
        #expect(price == nil)
    }

    @Test("Unavailable stays closed")
    func unavailableTerms() throws {
        #expect(try ClientController.cancelTerms(from: termsOutput(.unavailable)) == .unavailable)
    }

    @Test("A refused cancel-info keeps the provider's own words")
    func termsRefusalKeepsTheMessage() {
        let refusal = Operations.GetClaimCancelInfo.Output.notFound(
            .init(body: .json(.init(code: "404", message: "claim not found")))
        )
        do {
            _ = try ClientController.cancelTerms(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "claim not found")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("Claim info read the honest way — a refusal is the provider's sentence")
    func claimInfoRefusalKeepsTheMessage() {
        let refusal = Operations.GetClaimInfo.Output.notFound(
            .init(body: .json(.init(code: "404", message: "claim not found")))
        )
        do {
            _ = try ClientController.claim(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "claim not found")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("A refused cancel keeps the provider's words — 409 is the stale-version refusal")
    func cancelRefusalKeepsTheMessage() {
        let refusal = Operations.CancelClaim.Output.conflict(
            .init(body: .json(.init(code: "inappropriate_status", message: "Недопустимое действие над заявкой")))
        )
        do {
            try ClientController.cancelAccepted(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "Недопустимое действие над заявкой")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("A 200 body is not trusted — its status can read 'new' on a cancelled claim")
    func okBodyIsNotTheTruth() throws {
        // The Russian doc's own cancel example returns status "new". The boundary
        // accepts the answer and re-reads the claim rather than trusting it.
        let staleWorded = Operations.CancelClaim.Output.ok(
            .init(body: .json(.init(
                id: "c1", skipClientNotify: false, status: .new, version: 8
            ))))
        try ClientController.cancelAccepted(from: staleWorded)
    }

    @Test("Every wire status that means cancelled shares the prefix — all land in .other")
    func cancelledStatusesRecognized() {
        #expect(PlacedClaim.Progress(.cancelled).isCancelled)
        #expect(PlacedClaim.Progress(.cancelledWithPayment).isCancelled)
        #expect(PlacedClaim.Progress(.cancelledByTaxi).isCancelled)
        #expect(PlacedClaim.Progress(.cancelledWithItemsOnHands).isCancelled)
        #expect(!PlacedClaim.Progress(.accepted).isCancelled)
        #expect(!PlacedClaim.Progress(.estimatingFailed).isCancelled)
        #expect(!PlacedClaim.Progress(.readyForApproval).isCancelled)
    }

    @Test("Only an open claim with a wire id is worth offering to cancel")
    func cancellableGate() {
        func order(status: OrderStatus, claimID: String? = "c1") -> Order {
            Order(created: .now, status: status, route: [], claimID: claimID)
        }
        #expect(order(status: .searching).isCancellable)
        #expect(order(status: .active).isCancellable)
        #expect(!order(status: .searching, claimID: nil).isCancellable,
                "no claim id means nothing to cancel")
        #expect(!order(status: .done).isCancellable)
        #expect(!order(status: .cancelled).isCancellable)
        #expect(!order(status: .attention).isCancellable)
        #expect(!order(status: .draft).isCancellable)
    }

    @Test("A paid answer with no amount cannot be consented to — anywhere")
    func pricelessPaidIsNotConfirmable() {
        #expect(!ClaimCancellation.Terms.paid(price: nil, currency: nil).isConfirmable)
        #expect(!ClaimCancellation.Terms.unavailable.isConfirmable)
        #expect(ClaimCancellation.Terms.free.isConfirmable)
        #expect(ClaimCancellation.Terms.paid(price: 807.6, currency: "RUB").isConfirmable)
    }

    @Test("The boundary refuses to send a paid cancellation that never named its price")
    func pricelessPaidNeverReachesTheWire() async {
        // No client configured — the argument check must refuse before the wire
        // is even reached (review, PR #32).
        let controller = ClientController(tokenStore: TokenStore(service: "test.YDelivery"))
        await #expect(throws: CancellationPriceUnknown.self) {
            _ = try await controller.cancelClaim(
                id: "c1", version: 1, terms: .paid(price: nil, currency: nil)
            )
        }
    }

    @Test("Load, confirm, done — the confirm reports what the wire answered")
    func modelLoadConfirmDone() async {
        let model = OrderDetailView.Model()
        let asked = ClaimCancellation(status: .searching, version: 7, terms: .free)
        await model.load(using: { asked }).value
        #expect(model.cancellation == .ready(asked))

        var cancelled: ClaimCancellation?
        await model.confirm { cancelled = $0 }?.value
        #expect(cancelled == asked, "the cancel call gets the version and terms asked live")
        #expect(model.cancellation == .cancelled)
    }

    @Test("Unavailable terms never reach the cancel call")
    func modelRefusesUnavailable() async {
        let model = OrderDetailView.Model()
        await model.load(using: {
            ClaimCancellation(status: .searching, version: 3, terms: .unavailable)
        }).value
        var reached = false
        model.confirm { _ in reached = true }
        #expect(!reached, "a closed door stays closed — the button guards, the model insists")
    }

    @Test("A paid term without its amount is refused by the model's second guard")
    func modelRefusesPricelessPaid() async {
        let model = OrderDetailView.Model()
        await model.load(using: {
            ClaimCancellation(status: .searching, version: 3, terms: .paid(price: nil, currency: nil))
        }).value
        var reached = false
        model.confirm { _ in reached = true }
        #expect(!reached, "a charge nobody has seen is not a price anyone can agree to")
    }

    @Test("A failed ask renders its sentence, not a bare state")
    func modelFailedKeepsTheSentence() async {
        struct Refused: LocalizedError {
            var errorDescription: String? { "the wire's own words" }
        }
        let model = OrderDetailView.Model()
        await model.load(using: { throw Refused() }).value
        #expect(model.cancellation == .failed("the wire's own words"))
    }

    @Test("Accepted-but-unproven is its own state — the retry re-reads, never re-sends")
    func unconfirmedRechecksInsteadOfResending() async {
        let model = OrderDetailView.Model()
        await model.load(using: {
            ClaimCancellation(status: .searching, version: 7, terms: .free)
        }).value
        var resent = false
        await model.confirm { _ in
            resent = true
            throw CancellationUnconfirmed(status: nil)
        }?.value
        #expect(resent)
        guard case .unconfirmed = model.cancellation else {
            Issue.record("accepted-but-unproven must not render as a refused cancel: \(model.cancellation)")
            return
        }
        await model.recheck {}?.value
        #expect(model.cancellation == .cancelled,
                "observing the cancelled claim resolves the screen — no second mutation")
    }

    @Test("A still-standing claim keeps the unconfirmed state honest")
    func unconfirmedStaysWhenTheClaimStands() async {
        let model = OrderDetailView.Model()
        await model.load(using: {
            ClaimCancellation(status: .searching, version: 7, terms: .free)
        }).value
        await model.confirm { _ in throw CancellationUnconfirmed(status: nil) }?.value
        await model.recheck { throw CancellationUnconfirmed(status: "searching") }?.value
        guard case .unconfirmed = model.cancellation else {
            Issue.record("a claim still standing must stay unconfirmed: \(model.cancellation)")
            return
        }
    }

    @Test("Cancelled-but-unsaved retries the write, not the wire")
    func unrecordedRetriesTheWrite() async {
        let model = OrderDetailView.Model()
        await model.load(using: {
            ClaimCancellation(status: .searching, version: 7, terms: .free)
        }).value
        var wireTouched = false
        await model.confirm { _ in
            wireTouched = true
            throw CancellationUnrecorded(StoreController.StoreUnavailable())
        }?.value
        guard case .unrecorded = model.cancellation else {
            Issue.record("the disk's failure must not read as the wire's: \(model.cancellation)")
            return
        }
        wireTouched = false
        await model.retryRecording {}?.value
        #expect(model.cancellation == .cancelled)
        #expect(!wireTouched, "retrying the write must not re-ask the provider")
    }
}
