# Turning on login SMS (MSG91)

Written for whoever holds the MSG91 account and can edit `backend/.env`
on the server.

Until this is set up, the login OTP is not sent anywhere — it comes back
in the API response so a developer can read it off the screen. That is
fine on a laptop and unusable in production: anyone who calls the API
directly can read the code for any number and log in as them. Setting
this up is what closes that.

Unlike the payment keys, these go in `.env`, not the admin panel, and
the server has to be restarted to pick them up.

## 1. What you need from MSG91

Sign in at <https://control.msg91.com>.

| What | Where | Looks like |
|---|---|---|
| Auth Key | Settings → API → Auth Key | a 25-character string |
| Template ID | Campaigns → Templates (an **OTP** template) | `6xxxxxxxxxxxxxxxxxxxxxxx` |
| Sender ID | part of the template, e.g. `PARGIG` | 6 letters |

### The DLT part

Indian law requires every transactional SMS to be registered before it
can be sent. MSG91 walks you through it, but it is not instant — expect
a day or two:

1. Register the business on a DLT portal (Jio, Airtel, Vodafone — any
   one; they share a registry).
2. Register a **sender ID / header** — 6 letters, e.g. `PARGIG`.
3. Register the **message template**, with the code as a variable:
   > Your Pargig verification code is ##OTP##. Valid for 5 minutes. Do not share it with anyone.
4. Add the approved template in MSG91 as an **OTP** template. The id it
   gives you is `MSG91_TEMPLATE_ID`.

The template text must match what was approved **exactly**. A single
changed word and every message is rejected at the operator.

## 2. Put them in `.env`

On the server, in `backend/.env`:

```
MSG91_AUTH_KEY=your_auth_key_here
MSG91_TEMPLATE_ID=your_template_id_here
MSG91_SENDER_ID=PARGIG
```

Then restart the backend (`pm2 restart pargig`, or however it is run).

`.env` is gitignored and must stay that way — the auth key can send
messages on your account and spend your balance.

## 3. Prove it works

```
cd backend && npm run sms:test -- 9876543210
```

That sends one real message to that number, using the same code path a
login uses. It spends one SMS and creates nothing in the database.

- **It arrives** — done, logins now work over SMS.
- **"MSG91 refused: …"** — the message says which of the four things is
  wrong (auth key, template, balance, number).
- **MSG91 accepts it but nothing arrives** — the request id it prints is
  what their support needs. The message left here successfully; it was
  lost between MSG91 and the operator, usually DLT.

To check the wiring without spending a message, `npm run check:sms`
runs the whole flow against a local stub.

## 4. What changes once it is on

- `/auth/otp/request` stops returning `devOtp`. Nothing else in the API
  changes, and the app needs no rebuild for this.
- If MSG91 refuses a send, the request answers **502** and the code is
  not stored — so whatever code the user already has in their inbox
  keeps working rather than being silently replaced by one that never
  arrived.
- Turning it back off is one blank line in `.env` plus a restart. The
  dev path comes back, which is the escape hatch if MSG91 goes down.

## Rate limits

Every code now costs money, and `/auth/otp/request` is public and
unauthenticated. Three limits, all adjustable in `.env`:

| Limit | Default | Where it lives |
|---|---|---|
| `OTP_RESEND_COOLDOWN_SECONDS` | 30 | on the user record |
| `OTP_MAX_PER_DAY` | 10 per number, midnight IST | on the user record |
| `OTP_MAX_PER_IP_PER_HOUR` | 20 | in memory |

The per-number ones are on the user document rather than in memory
because a restart is exactly when someone is retrying, and a counter
that forgets on deploy is not a limit.

The per-IP one is skipped when the request appears to come from
127.0.0.1. That happens when the reverse proxy isn't passing the client
address on, and in that case every user looks like the same one —
capping them together would lock the whole app out at twenty logins an
hour. For it to work, Nginx needs:

```
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

Worth adding, but nothing breaks without it: the per-number caps are
the ones that bound the bill.

## Where the code lives

| File | What it does |
|---|---|
| `utils/sms.js` | the MSG91 call, and nothing else |
| `utils/otpThrottle.js` | the three limits above |
| `controllers/authController.js` | `requestOtp` — generate, send, store |
| `scripts/checkSms.js` | `npm run check:sms` |
| `scripts/sendTestSms.js` | `npm run sms:test` |

MSG91 can also generate and verify the code itself. We don't use that:
the code is made here, stored with its own expiry and attempt counter,
and checked here. MSG91 only carries it. That keeps one answer to "is
this code valid", keeps the no-SMS development path working, and means
an outage at MSG91 can never accept a login it shouldn't.
