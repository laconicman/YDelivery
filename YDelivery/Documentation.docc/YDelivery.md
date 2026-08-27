# YDelivery

@Metadata { @TechnologyRoot }

An unofficial iOS client for Yandex Delivery's Express (B2B Cargo) API — the app for a
person or a business that actually sends parcels: point-to-point, store-to-customer,
warehouse runs.

## Overview

Built on [`YandexDeliveryExpressAPI`](https://github.com/laconicman/YandexDeliveryExpress),
whose hand-written OpenAPI document is the only machine-readable contract this API has. Its
sibling [`YandexDeliveryExpressDemo`](https://github.com/laconicman/YandexDeliveryExpressDemo)
demonstrates that package honestly, rough edges included; **this app is the opposite bet** —
it hides the API behind the experience a courier app owes its user: pick points on a map,
compare offers, track the courier, keep history.

<doc:Vision> holds the capability map — what the API offers, what similar apps do with it,
and what this app will build, in order. For anything about the API's actual behaviour, the
package's `WorkingWithYandex` article outranks every assumption.

## Topics

### Project Direction

- <doc:Vision>
- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>
