# YDelivery

@Metadata { @TechnologyRoot }

A general-purpose iOS delivery app — for a person or a business that actually sends
parcels: point-to-point, store-to-customer, warehouse runs. Delivery providers plug in
behind a single boundary; each integration stays unofficial and unbranded.

## Overview

The first integration is Yandex Delivery's Express (B2B Cargo) API, through
[`YandexDeliveryExpressAPI`](https://github.com/laconicman/YandexDeliveryExpress),
whose hand-written OpenAPI document is the only machine-readable contract that API has.
Its sibling
[`YandexDeliveryExpressDemo`](https://github.com/laconicman/YandexDeliveryExpressDemo)
demonstrates that package honestly, rough edges included; **this app is the opposite bet** —
it hides the API behind the experience a courier app owes its user: pick points on a map,
compare offers, track the courier, keep history. That shape is provider-agnostic on
purpose: the store, the library, the sharing and the record signing know nothing about
which integration answered.

<doc:Vision> holds the capability map — what a provider's API offers, what similar apps do
with it, and what this app will build, in order. For anything about an integrated API's
actual behaviour, its package's own catalog outranks every assumption — for Yandex,
`WorkingWithYandex`.

## Topics

### Project Direction

- <doc:Vision>
- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>
- <doc:Collaboration>
- <doc:Schema>

### Specifications

- <doc:DesignSystem>
- <doc:LinkGrammars>
