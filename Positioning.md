# What this app is for

Draft prose for the App Store description, the README's opening, and anything else that has
to explain the app to someone in one breath. Derived from what the API makes possible and
what the interface has to do about it — which is an unusual way to arrive at positioning,
but it means nothing here is a promise the app cannot keep.

---

## The short version

**A phone app for the people who send the parcels.**

Yandex Delivery's Express API was built for shops: for a warehouse with a CRM, an
integration team, and a developer to call it. Signing up for it directly is a little
tedious — there is an agreement to sign — and once you have, you get the whole thing.
Every tariff from a courier on a scooter to a van with two loaders. Routes with several
stops, including sending the remainder back. Scheduled pickups. Declared value.

And then, if you are one person rather than a company with a back office, you get nothing
to run it with.

That is the gap. Between one-off parcels in a superapp and a warehouse with software, there
is a large group of people for whom the delivery *is* the business: the workshop that ships
what it made this morning, the store with one shelf and a courier twice a day, the person
who signed the agreement because the full API was cheaper and more capable than the
consumer route. This app is their software.

---

## Three things it does that the alternatives don't

**The full tariff range, not the consumer subset.** Cargo classes with loaders, weight and
size limits stated in plain language, options like a thermal bag or door-to-door, scheduled
pickup windows. The classes are shown before the route is priced, because for a sender they
are not a payment choice — a van and a scooter are different routes.

**Orders that stay yours.** The vendor's history window is short. Everything this app
records — routes, contacts, items, prices, statuses — lives on the device and stays there,
offline, for as long as you keep it. Repeat last Tuesday's warehouse run in one tap. Look up
what you sent in March.

**Your own identifiers on every order.** This is the part the API cannot do for you and the
part that matters most day to day. A delivery is never just a delivery: it is order #4417,
or the transfer that cleared on Thursday, or the invoice you have to attach to it. Which
identifiers those are is different for every business and identical inside one — so you
define your fields once, and every order carries them, and every order is findable by them.
The parcel is not the unit of work. The order is.

---

## Who it is for

**The one-person operation.** You make it, you sell it, you send it. You have no CRM
because you *are* the CRM. You need capability without integration.

**The small shop that outgrew the consumer app.** A few orders a day, several stops on a
run, occasionally something heavy enough to need a van and someone to carry it. You need
multi-point routes and real tariffs, and you need last week's route back without retyping
it.

**The person who signed up for the API and found no client.** The dashboard is a browser
tab; the integration is a project. This is neither.

*Later, and honestly labelled as an idea rather than a feature:* the other side of the same
problem — keeping track of what other people are sending **to** you. The API does not offer
it, so it would be the app's own record-keeping rather than live tracking, and it should
only ship if it can be useful without pretending to be something it isn't.

---

## What it is not

It is an **unofficial client**. It is not made by, endorsed by, or affiliated with the
provider. It carries none of their branding, and it does not resell delivery: you bring your
own account and your own token, the app talks to the API on your behalf, and the money and
the agreement are between you and them.

It is also **not a courier-hailing app**. It looks a little like one because the domain is
shared, but the person using it is not the person travelling, and every screen assumes you
are arranging something for someone else — usually while doing something else.

Nothing leaves the device except the order itself: no account with us, no sync, no
analytics on where you send things.

---

## Lines that can be lifted directly

Short, for the App Store subtitle or a README first line:

- Send parcels with the whole API, from your phone.
- The delivery app for people who are the whole business.
- Full tariffs, multi-point routes, and your own order numbers on every delivery.

One paragraph, for a store description's opening:

> YDelivery is an unofficial iOS client for Yandex Delivery's Express API — the interface
> the API never came with. Bring your own account, and get the full range: courier, express
> and cargo classes with their real limits, multi-point routes, scheduled pickups, declared
> value. Your orders are stored on the device and stay there, so repeating last week's run
> takes one tap. And because a delivery is always part of something bigger, you define the
> fields your business actually uses — order number, invoice, transfer id — once, and every
> delivery carries them.

For the "why this exists" note, if the README wants one:

> The API is written for shops with developers. Most of the people who could use it are one
> person with a phone. This is the missing half.

---

## A note on tone, for whoever writes the rest

Two failure modes to avoid. The first is superapp cheerfulness — this is a tool used under
time pressure by someone whose money is in the parcel. The second is API vocabulary: claims,
offers, taxi classes and route points are the vendor's words, and none of them should ever
reach the interface or the store page. Say courier, van, stop, order, price.
