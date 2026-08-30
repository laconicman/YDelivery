# Link Grammars

Parser specification: how a pasted map link or raw coordinate string becomes a route point.
Lifted from the research dossier (its transient home) because this outlives any design
session — it is the contract the paste affordance's implementation honors, and its tests
cite. Verified against provider documentation 2026-08; re-verify a rule before relying on
it in a dispute, and record the date.

## What the design promises, per provider

| Source | Example | Coordinate rule | Offline-parseable? |
|---|---|---|---|
| **Yandex Maps, point** | `https://yandex.ru/maps/?pt=30.335429,59.944869&z=18` | `pt` = **lon,lat** (docs: longitude first) | ✅ |
| Yandex Maps, center | `…?ll=30.310182,59.951059&z=12` | `ll` = **lon,lat** — map center, weakest signal; use only if no `pt`/`whatshere` | ✅ |
| Yandex Maps, "what's here" | `…?whatshere[point]=37.444076,55.776788` | **lon,lat** | ✅ |
| Yandex Maps, route | `…?rtext=59.967870,30.242658~59.898495,30.299559&rtt=auto` | `rtext` = **lat,lon**~lat,lon (⚠ opposite order!) — offer *both ends* as from/to | ✅ |
| Yandex Maps, search-text coords | `…?text=55.762611,36.982528` | `text` may hold **lat,lon** as a plain string | ✅ |
| Yandex Maps, org card | `https://yandex.ru/maps/org/1184371713` | `oid` only — **no coordinates in the URL** | ❌ needs network (or decline gracefully) |
| Yandex Maps, short | `https://yandex.ru/maps/-/CDUaELzY` | expands via HTTP redirect to a full `/maps/?ll=…&text=…` URL | ❌ one GET, then rules above |
| **Google Maps, query pin** | `https://www.google.com/maps?q=55.7558,37.6173` or `…/maps/search/?api=1&query=55.7558,37.6173` | `q`/`query` = **lat,lng** | ✅ |
| Google Maps, path view | `https://www.google.com/maps/@55.7558,37.6173,15z` | `@lat,lng,zoom` = **map center**, not the pin — fallback only | ✅ |
| Google Maps, place data blob | `…/maps/place/…/data=!3d55.7558!4d37.6173…` | `!3d{lat}!4d{lng}` is the actual place pin — prefer over `@` | ✅ |
| Google Maps, short | `https://maps.app.goo.gl/Abc123`, `goo.gl/maps/…` | expand via redirect(s), then rules above | ❌ network |
| **2GIS, point card** | `https://2gis.ru/geo/82.683276,55.001485` | `/geo/` = **lon,lat** | ✅ |
| 2GIS, object card | `https://2gis.ru/geo/141476222740947`, `/firm/{id}` | numeric ID — no coordinates | ❌ (decline, or resolve via their API — out of scope) |
| 2GIS, directions | `https://2gis.ru/directions/points/37.531542,55.736291;{id}\|37.665247,55.759725;{id}` | points = **lon,lat**(;object_id), `\|`-separated — offer both ends | ✅ |
| 2GIS, short | `https://go.2gis.com/7muvw` | expand via redirect, then rules above | ❌ network |
| **geo: URI (RFC 5870)** | `geo:55.7558,37.6173`, `geo:13.4125,103.8667,14` | **lat,lng[,alt]**, WGS-84 default; `;u=` (uncertainty) may follow; Android extension `geo:0,0?q=lat,lng(label)` | ✅ |
| **Apple Maps, classic** | `https://maps.apple.com/?ll=48.85837,2.29448&q=Label` | `ll` = **lat,lng**; `q` becomes the pin label when `ll` present; `address=` is a geocode string | ✅ (`ll`); `address`-only needs geocoding |
| Apple Maps, unified (iOS 18.4+/web) | `https://maps.apple.com/place?coordinate=40.779092,-73.962932&name=…` | `coordinate` = **lat,lng**; `place-id` forms carry no coords | ✅ (`coordinate`) |
| **Raw string** | `55.7558, 37.6173`, `55.7558N, 37.6173E`, DMS `55 45 20.9N …` | assume **lat,lon** for bare pairs (universal human convention; matches geo:/Apple/Google) | ✅ |

## The two traps

**Coordinate order flips per provider.** Yandex/2GIS web params are lon,lat; Yandex
`rtext`, `geo:`, Apple, and Google are lat,lng. West of the Urals both values are ≤ 90, so
magnitude cannot disambiguate — **the parser keys on host + parameter, never guesses.** The
design consequence: the paste affordance always shows the resolved point as a mini-map or
address for human verification before it joins the route, because a silent lon/lat swap
puts the pin in the Barents Sea.

**Short links are the only network-dependent class** (`yandex.ru/maps/-/…`,
`maps.app.goo.gl`, `goo.gl/maps`, `go.2gis.com`): a brief "Разворачиваем ссылку…" state on
the suggestion row, with offline copy («Не получилось развернуть короткую ссылку без
сети»). And per iOS pasteboard privacy, the affordance is a **button** (or
`UIPasteboard.detectPatterns`) — never an ambient pasteboard scan.

## Sources

Yandex launch-URL docs (https://yandex.com/dev/yandex-apps-launch-maps/doc/en/concepts/yandexmaps-web) ·
Yandex short-link expansion example (https://community.glideapps.com/t/expand-short-link-to-glide/66837) ·
Google Maps URLs (https://developers.google.com/maps/documentation/urls/get-started) ·
Google link-parsing taxonomy incl. `@` vs `!3d!4d` (https://github.com/kdcokenny/google-maps-link-parser,
https://practicaltools.co/guides/how-to-get-coordinates-from-google-maps) ·
legacy `q=lat,lng` behavior (https://stackoverflow.com/questions/11354211/google-maps-query-parameter-clarification) ·
2GIS deeplinks (https://help.2gis.ru/question/razrabotchikam-zapusk-ideystviya-vmobilnom-prilozhenii-cherez-deeplink) ·
2GIS short links in the wild (https://npm.io/package/map2map-converter) ·
RFC 5870 (https://www.rfc-editor.org/rfc/rfc5870.html) ·
Android `geo:` extension (https://developer.android.google.cn/guide/components/google-maps-intents) ·
Apple classic map links (https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html) ·
Apple unified URLs (https://developer.apple.com/documentation/mapkit/unified-map-urls).

## See Also

- <doc:DesignSystem>
- <doc:Vision>
