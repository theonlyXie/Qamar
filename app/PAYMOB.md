# Turning on Paymob (no code)

Qamar+ in Egypt is billed through **Paymob**, in **Egyptian pounds**. People can pay with a card (Visa, Mastercard, Meeza) or an Egyptian mobile wallet (Vodafone Cash, Orange Cash, and the others Paymob enables on your account). Su Points are still earned only — they are never sold.

The app and the server are already wired for this. Your job is the business side: a Paymob merchant account, approval, and pasting four secrets into Supabase. Until those secrets exist, the paywall tells the truth and does not pretend a payment went through.

## Prices (EGP)

| Plan | What they pay | What you keep in mind |
|---|---|---|
| Monthly | **500** | The only plan. No annual, no family tier, no discounts — those wait on month-2 retention. |
| Professional's code | **500** | The client pays the same 500. The nutritionist or coach who gave the code is owed **100 EGP a month (20%) for 12 months** from the client's first payment, in their EGP wallet. This is not Su Points. |

The phone never decides the price. Checkout asks the server; the server stamps the amount Paymob collects. A later campaign code (the earned-month promo, Ramadan) goes in the `promo_codes` table as `kind = campaign` — you do not need another app release to add one.

The professional's dashboard: `POST /billing/affiliate/clients` lists the clients who typed this professional's code **and said yes to sharing** (consent type `adherence_share`, migration 0053 — a switch under the code field and on Me, off until turned on, withdrawable), with the last seven days as numbers only: days logged, days within 10% of the target, the average, the target. Never meals, photos or weight. A client is listed only while their twelve months with the professional run.

Professional payouts: the nutritionist taps **Redeem EGP** once the wallet has at least 50 EGP. That opens a `requested` payout. You send the money from the company account (bank / InstaPay) and mark the row `sent`. Do not pay this out of Su Points.

## What is already settled

- **The earned month, once.** `POST /billing/earned` says where a member stands in the promo — 28 logged days in the first 30 days of paid membership — and `POST /billing/earned/claim` grants 30 more days of Qamar+ when they are reached (migration 0052, `earned_months`). The days are counted from `meal_logs` when asked, the window opens on the Cairo day of the first paid order, and the grant is appended to the running month the way a renewal is; a lapsed member gets a fresh 30 days with `provider = 'earned'`. The app claims it the moment it is due and shows the progress while it is being earned.
- **A free week, once.** `POST /billing/trial/start` gives seven days of Qamar+ with no card. Its one reminder is scheduled on the phone the moment the trial starts, 48 hours before the week ends, and the Today card carries the same question inside those 48 hours. The database (`plus_trials`, migration 0043) allows one per account, never after a payment, and a later Paymob payment simply replaces the trial entitlement. Nothing renews on its own: when the week ends the person is back on Lite.

- Talking to Qamar writes the meal plan.
- Lite is three meal photos and three questions a day. Extra photos are bought with earned Su, not cash; the fourth question is Qamar+.
- Qamar+ checkout opens Paymob’s hosted page. The phone **never** marks someone as paid. Paymob tells our server; the server turns Qamar+ on.

## Steps for you

### 1. Create a Paymob Egypt account

Go to [paymob.com](https://paymob.com) and register as a business in **Egypt**. Pick online payments / e-commerce, not in-person POS.

Use the same company name and tax details you will put on the app and on dr-qamar.com.

### 2. Complete merchant verification

Paymob will ask for the usual Egyptian merchant pack. Have these ready:

- Commercial register
- Tax card
- National ID of the responsible person
- A bank account in the company’s name (this is where settlements land)
- A short description of Qamar: a nutrition app, digital subscription, prices in EGP
- Links to the live **privacy policy** and **terms** (`https://dr-qamar.com/privacy` and `/terms`)

They will not give live keys until this file is accepted. That wait is normal.

### 3. Stay on test keys until the first real card works in test

In the dashboard you will see **test** and **live**. Do not switch to live yet.

### 4. Copy four values from the dashboard

Open **Settings → API Keys** (wording may be “Developers”):

| What they call it | What we need it as |
|---|---|
| Secret key | `PAYMOB_SECRET_KEY` |
| Public key | `PAYMOB_PUBLIC_KEY` |
| HMAC secret | `PAYMOB_HMAC_SECRET` |
| Integration ID for **card** (and wallet if you want wallets) | `PAYMOB_INTEGRATION_IDS` |

If you have more than one integration ID (card + wallet), write them in one line, separated by commas, no spaces: `123456,789012`.

Test IDs only work with the test secret. Live IDs only work with the live secret. Mixing them is the usual reason checkout says the integration does not exist.

### 5. Turn on the Egyptian methods you actually want

Still in the dashboard, enable at least:

- Card (Visa / Mastercard)
- Meeza if they offer it on your account
- Mobile wallets (Vodafone Cash, Orange Cash, e& / We Pay) if you want those on day one

Not every method is on by default. If a method is missing, write to Paymob support from the dashboard rather than changing the app.

### 6. Paste the secrets into Supabase

In the Supabase project (`stqirjlqzchcoeegumoq`):

1. Open **Project Settings → Edge Functions → Secrets**.
2. Add the four names from the table above, with the values from Paymob.
3. You do **not** put these in the phone app, in GitHub, or in chat.

Then apply the billing migration and deploy the billing function (or run **Deploy Qamar** after this work is merged — it will publish `billing` as well as the assistant).

The webhook Paymob should call is:

`https://stqirjlqzchcoeegumoq.supabase.co/functions/v1/billing/webhook`

If the dashboard has a field for “notification URL” / “callback URL”, paste that. If it does not, the server already sends it with every checkout.

### 7. Do one test payment

1. Open Qamar while signed in (a guest must link an account first — we have to know who paid).
2. You → Qamar+ → **Start Qamar+** (EGP 500). With a professional's code the price is still 500; the code only attaches their share.
3. Paymob’s page opens. Use Paymob’s **test card** from their documentation (not a real card).
4. Finish. You come back to the app. Tap **Confirm subscription** if Qamar+ is not on yet — Paymob’s confirmation can land a few seconds later.

If it never turns on: the HMAC secret is usually wrong, or the webhook URL is not reachable. Check **Edge Function logs** for `billing`. Do not “force” Plus from the phone.

### 8. Go live

When test payments succeed and Paymob has approved the merchant file:

1. Replace the four secrets with the **live** keys and live integration IDs.
2. Make one real payment of 500 EGP on a real card or wallet, then refund it from the Paymob dashboard if you do not want to keep it.
3. Confirm the bank settlement account is the company account.

### 9. After that, leave it alone

- Refunds and chargebacks are handled in the Paymob dashboard. The next time the app checks, Qamar+ follows what Paymob last confirmed.
- Auto-renew (charge the card every month without asking) is a separate Paymob product called Subscriptions. This first version is **pay for a month at a time**. When you want auto-renew, turn Subscriptions on in the Paymob dashboard and tell us — the app does not invent a renewal it cannot collect.
- Su Points stay earned. Never sell them through Paymob. The professional's share is a separate EGP wallet.

## If you later put Qamar on the Apple App Store

Apple still requires its own In-App Purchase for digital subscriptions inside an iOS App Store app. Paymob remains the right gateway for Egypt (EGP, Meeza, wallets) on Android, web, and any distribution that is not the Apple store. Do not mix the two in one iOS App Store binary without legal advice.

## Who to call when something is stuck

- Paymob merchant / KYC: your dashboard support, or `support@paymob.com`
- Keys saved but checkout still refuses: confirm test-vs-live match, then the integration IDs
- Paid in Paymob, Qamar+ still off: HMAC secret and the webhook URL above
