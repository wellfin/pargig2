# Turning on Razorpay

Written for whoever holds the Razorpay account and the admin panel login.

No code change, no deploy, no `.env` edit. Everything below is typed
into the admin panel once and takes effect on the next payment.

## 1. Get the keys from Razorpay

In the Razorpay dashboard: **Account & Settings → API Keys → Generate Key**.

You get two strings:

| What | Looks like | Notes |
|---|---|---|
| Key ID | `rzp_test_AbCdEf1234` or `rzp_live_...` | Public. Safe to send to the app. |
| Key Secret | a 24-character string | **Shown once.** If you lose it, generate a new pair. |

Start with **test** keys. A live key charges real cards from the moment
it is saved.

## 2. Save them in the admin panel

**Settings → Payment Gateway**

1. Provider → **Razorpay**
2. Paste the Key ID and Key Secret
3. Tick **Enabled**
4. **Save**, then **Test Connection**

Test Connection asks Razorpay whether the saved credentials work. A
green message means payments will go through; anything else means they
would not have.

The key secret is encrypted before it is stored and is never shown
again — the panel displays a mask. Leaving the secret field blank when
you save keeps the one already held, so you can change other settings
without retyping it.

Only **superadmin** and **finance** admins can open this page.

## 3. Add the webhook

The panel shows the URL to use. In Razorpay: **Account & Settings →
Webhooks → Add New Webhook**.

- **URL** — the one shown on the Settings page, e.g.
  `http://your-server/api/payments/webhook/razorpay`
- **Secret** — invent one, paste the same string into the panel's
  *Webhook Secret* field, and save both
- **Events** — `payment.captured`, `payment.failed`, `refund.processed`

Payments work without a webhook. What breaks without one: a payer who
loses signal or closes the app between paying and the app confirming.
Their money is taken, and nothing on our side hears about it. The
webhook is what settles that job anyway.

## 4. Going live

Generate live keys in the dashboard, paste them in, Save, Test
Connection. The panel reads test-or-live from the key itself rather
than from a dropdown, so it cannot be mislabelled.

Razorpay requires KYC before live keys are issued.

---

## How it hangs together

```
app                         server                      razorpay
 |  "I want to pay job X"      |                            |
 |---------------------------->|                            |
 |                             |  create order (amount from |
 |                             |  the job, not the app)     |
 |                             |--------------------------->|
 |  order id + key id          |                            |
 |<----------------------------|                            |
 |  opens checkout sheet ------------------------------------>|
 |  payment id + signature <----------------------------------|
 |  "here is the proof"        |                            |
 |---------------------------->|  verify signature          |
 |                             |  ask razorpay the status   |
 |                             |--------------------------->|
 |  receipt                    |  credit worker, settle job |
 |<----------------------------|                            |
                               |<-- webhook (belt and braces)
```

Things worth knowing:

- **The amount is always the server's.** Orders are recorded when
  opened, and settlement reads the amount back from that record. The
  app cannot pay ₹1 and claim ₹10,000.
- **Settlement happens once.** The in-app confirmation and the webhook
  race each other; whichever wins claims the order, and the loser is
  told it is already done.
- **Switching the gateway off** falls back to the built-in stand-in
  rather than breaking every Pay button. Useful if Razorpay has an
  outage; obviously no real money moves while it is off.
- **Cash and wallet payments never touch Razorpay.** Cash was handed
  over in person; a wallet payment is money the server already holds.
- **Refunds** go back through Razorpay when the payment came through
  it. Cash and wallet refunds have to be paid out by hand, and the
  admin panel says so rather than claiming a refund that never left.

## Where the secrets live

| Secret | Where it goes | Why |
|---|---|---|
| Razorpay Key ID | Admin panel (and sent to the app per payment) | Public |
| Razorpay Key Secret | Admin panel → encrypted in MongoDB | Signs payments |
| Webhook Secret | Admin panel → encrypted in MongoDB | Signs webhooks |
| `SETTINGS_ENCRYPTION_KEY` | Server `.env` (optional) | Encrypts the two above. Falls back to `JWT_SECRET` if unset. |

Encryption is AES-256-GCM. A database dump on its own does not yield
the keys — the attacker also needs the server environment.

If you ever set `SETTINGS_ENCRYPTION_KEY` **after** saving credentials,
or change it, the stored secrets can no longer be decrypted: the panel
will show the gateway as unconfigured and you re-paste the key secret.
Nothing silently half-works.

## Checking it

```
cd backend && npm run check:gateway
```

67 assertions against a throwaway database: signature maths, secrets at
rest, the admin API, webhook handling, and the amount-safety rules
above. It never calls Razorpay and never touches the real database.
