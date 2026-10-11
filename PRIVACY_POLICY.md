# Honest Signal — Privacy Policy

**Last updated: 11 October 2026**

**Publisher: Froggy Eye Ltd (United Kingdom)**

**Contact: info@froggyeye.com**

## The short version

Honest Signal collects nothing about you. There is no account, no sign-in, no
analytics, no advertising, no tracking, and no crash-reporting service. Nothing
you do in the app is sent to Froggy Eye Ltd, and we have no server that could
receive it.

## What the app stores, and where

Everything Honest Signal records stays in the app's private storage on your own
device:

- **Your measurements** — the connection scores, latencies, speeds and network
  types the app measures. These are kept for up to 25 hours and then deleted
  automatically. With Pro they are kept for up to 30 days: the most recent 25
  hours in full, and older readings reduced to the worst reading in each five
  minutes. You can delete them all at once from the History screen.
- **Your settings** — sampling intervals, indicator style, speed-sample cutoff,
  theme.
- **Your Pro purchase status** — a single flag recording that the unlock was
  bought.

On Android, the home-screen widget and Quick Settings tile read the latest
score from the same private storage.

Uninstalling the app removes all of it. It is not included in cloud backup or
device-to-device transfer.

## The network requests Honest Signal makes

Measuring a connection means using it, so the app makes real network requests.
It sends small HTTPS requests to well-known public connectivity-check and
speed-test endpoints operated by Google and Cloudflare — the same kind of
endpoint your phone's operating system already uses to detect Wi-Fi sign-in
pages:

- `www.gstatic.com`, `connectivitycheck.gstatic.com` (Google)
- `cp.cloudflare.com`, `speed.cloudflare.com` (Cloudflare)

These requests carry no account or app identifier and no cookie. As with any
web request, the operator of the endpoint sees the IP address it came from and
handles it under their own privacy policy. Honest Signal does not send those
operators anything else. It uses response timing and transfer bytes only to
measure connection performance.

You can control this traffic in Settings. The daily cutoff pauses larger speed
samples once the displayed amount is reached; small latency checks continue, so
total measurement traffic can exceed the cutoff. Shorter intervals use more
data and battery. You can lengthen the interval or switch off measuring on
mobile data entirely.

## Home-screen widget (iOS)

The iOS widget measures on its own, because iOS gives the app no time to
measure in the background. Whenever iOS refreshes it, the widget sends a few of
the same small latency requests to the Google and Cloudflare endpoints listed
above and shows the result. It stores nothing beyond the reading it displays
and sends nothing else.

## Reports you export (Pro)

The History screen can export a PDF report or a CSV file of your readings.
These are created on your device and handed to your phone's share sheet; they
go only where you choose to send them. They contain the readings' times,
scores, speeds and network types (Wi-Fi or mobile), and no device, account or
location identifiers.

## Ratings and feedback

Honest Signal may occasionally show the App Store or Google Play rating prompt.
That prompt is the store's own; the app learns nothing about whether or how you
rated it. "Send feedback" opens your email app addressed to
info@froggyeye.com — if you send it, we receive what you wrote and your email
address, and use them only to reply.

## Purchases

Honest Signal Pro is a one-off purchase handled entirely by the App Store or
Google Play. Froggy Eye Ltd never sees your payment details. The stores tell
the app only whether the purchase exists, and the app records that locally so
Pro features stay unlocked. Restoring a purchase on a new device asks the same
question of the same store.

## Permissions

- **Notifications (Android)** — the live signal indicator *is* a notification;
  its icon is the score. Optional drop-out alerts (Pro) are also local
  notifications, created on the device from its own readings. Declining
  notifications leaves the rest of the app working.
- **Display over other apps (Android, optional)** — draws the floating bubble.
  Off by default, requested only when you turn the feature on, and revocable in
  Android settings at any time.
- **Run at startup (Android)** — brings back the status-bar indicator you had
  switched on after a restart.
- **Network state** — tells the app whether you are on Wi-Fi or mobile data.

No permission is used to collect, derive or transmit information about you.

## Children

Honest Signal is a utility with no user-generated content, no social features and
no advertising. It is suitable for all ages and collects no data from anyone,
including children.

## Your rights

Because we hold no data about you, there is nothing for us to disclose, correct
or delete on request. Everything the app stores is on your device and under
your control. If you would like anything here explained, write to
info@froggyeye.com.

## Changes

If this policy ever changes, the updated version will be published at this
address and the date at the top will change.

© 2026 Froggy Eye Ltd
