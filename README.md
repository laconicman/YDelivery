# YDelivery

An **unofficial** iOS client for Yandex Delivery's Express (B2B Cargo) API — for people and
businesses that send parcels: point-to-point, store-to-customer, warehouse runs. Built on
[`YandexDeliveryExpressAPI`](https://github.com/laconicman/YandexDeliveryExpress).

> Unaffiliated with Yandex. The API has no published OpenAPI document; the package's is
> hand-written and validated against live traffic. This app deliberately carries no Yandex
> branding.

Its sibling, [`YandexDeliveryExpressDemo`](https://github.com/laconicman/YandexDeliveryExpressDemo),
demonstrates the package honestly, rough edges included. This app is the product bet: the
user never sees a "claim".

## Documentation

The DocC catalog is authoritative for this app's direction:

| Article | What it answers |
|---|---|
| [Vision](YDelivery/Documentation.docc/Vision.md) | What this app is; the capability map (API surface → feature → phase) |
| [Design](YDelivery/Documentation.docc/Design.md) | Load-bearing decisions, each with the rejected alternative |
| [Roadmap](YDelivery/Documentation.docc/Roadmap.md) | Priority order, phase by phase |
| [Tech Debt](YDelivery/Documentation.docc/TechDebt.md) | Every compromise carried (`YD-n`) |

For anything about the API itself, the package's catalog is authoritative — start with
[Working with the Yandex API](https://github.com/laconicman/YandexDeliveryExpress/blob/main/Sources/YandexDeliveryExpressAPI/YandexDeliveryExpressAPI.docc/WorkingWithYandex.md).

Render locally:

```console
% xcodebuild docbuild -scheme YDelivery -derivedDataPath .build/docs \
    -skipPackagePluginValidation
```

## Building

Requires iOS 17 / Xcode 26. The package dependency is by URL at `0.2.x`;
`Package.resolved` is committed. For cross-editing the package locally, drag its folder into
the project — a local package overrides the remote of the same name, so the manifest never
changes.

```console
% xcodebuild build -scheme YDelivery \
    -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation
```

`-skipPackagePluginValidation` is required: the package runs the OpenAPI generator build
plugin, and non-interactive builds otherwise fail on its trust prompt.

Authentication is an OAuth token from the Yandex Delivery profile, entered in the app and
stored in the Keychain. Never commit a token.

## License

Apache 2.0 — see [LICENSE](LICENSE).
