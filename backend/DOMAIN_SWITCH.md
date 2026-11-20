# Moving from the IP to a domain

Today the server answers on `3.111.232.213`. This is what changes
when a domain is bought, and — more usefully — what does not.

## Nothing in the backend hardcodes the address

Checked, not assumed:

- **The Razorpay webhook URL** shown in Settings is built from the
  request (`publicOrigin`), honouring the `X-Forwarded-*` headers
  nginx sets. Open the panel on the domain and it shows the domain.
- **Nothing is sent to Razorpay that contains our address.** No
  `callback_url`, no `redirect`, no `notify_url`. Razorpay only ever
  calls the webhook you paste into their dashboard.
- **CORS is open** (`cors()` with no origin list), so a new domain is
  not blocked.
- **Uploaded files** are either absolute S3 URLs or host-relative
  `/uploads/...` paths. Neither carries a hostname of ours.
- **MSG91 and the distance providers are outbound only.** They call
  nobody back, so they do not care what we are called.

So the backend needs no code change. The work is nginx, TLS, the
Razorpay dashboard, and the mobile app.

## The order that avoids downtime

**1. Point the domain at the server, keep the IP working.**

Add the domain to the existing nginx server block rather than
replacing the IP:

```nginx
server_name 3.111.232.213 pargig.in www.pargig.in;
```

Both must answer for a while. Every phone that already has the app is
pinned to the IP (see below) and will keep calling it until it gets a
new build. Switching the IP off the day the domain goes live breaks
every existing install.

**2. Get a certificate.**

```
sudo certbot --nginx -d pargig.in -d www.pargig.in
```

Certbot rewrites the server block and adds the redirect. Leave the
plain-HTTP IP listener alone — old app builds use `http://` and will
stop working if everything is forced to HTTPS on a name they do not
use.

**3. Pin the webhook URL before touching Razorpay.**

In `backend/.env`:

```
PUBLIC_ORIGIN=https://pargig.in
```

and restart. Without this, opening the panel on the IP out of habit
hands you an IP webhook URL to paste into Razorpay — which works
until the IP changes and then fails quietly, because a webhook nobody
calls looks exactly like one that was never needed.

**4. Update the webhook in the Razorpay dashboard.**

Settings → Third party shows the URL to paste, and the events to
subscribe to. Changing it there does not affect payments already in
flight; it only changes where the confirmation is delivered.

**5. Rebuild the app.**

In `mobile/lib/config.dart`:

```dart
static const _prodApiBase = 'https://pargig.in';

static const _retiredHosts = [
  '52.66.245.202',
  '3.110.101.117',
  '3.111.232.213',   // add it, never remove an entry
];
```

The retired list is what releases phones from their pin. On first
launch the app writes the then-current address to disk, so an install
keeps calling that address forever unless the host is listed as
retired — and the check runs in the app, which means **a phone has to
receive the new build before it moves**. That is the whole reason
step 1 says keep the IP alive.

## What does not need doing

- **MSG91** — no URL of ours is involved. Nothing changes.
- **OSRM / Google distances** — outbound calls. Nothing changes.
- **The admin panel** — served from the same origin and calls `/api`
  relatively, so it follows whatever address it was opened on.
- **S3** — bucket URLs are absolute and independent of ours.

## Afterwards

The IP listener can be removed once the app's install base has had
time to update — months, not days, and there is no way to measure it
from here. Until then it costs one line of nginx config, which is
cheaper than a user whose app silently stops working.
