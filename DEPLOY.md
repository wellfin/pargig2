# Pargig — Deploy on AWS via Git (end-to-end)

This guide takes a clean AWS account and ends with:

- **Backend API** (Node.js) running on an EC2 Ubuntu box, behind Nginx, under PM2
- **Admin frontend** (React/Vite) built into static files, served by the same Nginx
- **Database** on MongoDB Atlas free tier
- **Updates** pushed to GitHub → pulled onto EC2 with a one-line script
- (Optional) **HTTPS** via Let's Encrypt + auto-deploy via GitHub Actions

The mobile app stays as-is — it just points at the new API URL via the in-app
"Server settings" screen.

> **Region used in examples:** `ap-south-1` (Mumbai). Pick whatever is closest
> to your users; commands don't change.
> **Domain used in examples:** `api.example.com` and `admin.example.com`. Replace
> with your real domain (or skip the domain step and use the raw EC2 IP).

---

## 👉 Where to start — your roadmap

Do the sections **in this exact order**. Don't skip ahead — each builds on the
last. If you stop and come back later, find the highest-numbered step you
finished and resume from the next one.

### Phase 1 — Get the server up (do this first)
- §0 — Pre-requisites you need on your laptop
- §1 — Launch the EC2 Ubuntu server
- §2 — SSH into the box from your laptop
- §3 — Connect FileZilla for file transfers
- §4 — **Server base setup** (Node, Git, Nginx, PM2) ← *don't skip*

### Phase 2 — Database
- §5 — MongoDB Atlas free cluster + connection string

### Phase 3 — Deploy the app
- §6 — Clone the repo onto EC2
- §7 — `.env` + Firebase service account via FileZilla
- §8 — Run the backend under PM2
- §9 — Nginx reverse proxy
- §10 — Build & deploy the admin frontend

### Phase 4 — Make it usable
- §11 — Point the mobile app at the new API
- §12 — *(Optional)* Domain + HTTPS via Let's Encrypt

### Phase 5 — Updates from now on
- §13 — Deploy workflow (the `git pull` loop)
- §14 — *(Optional)* GitHub Actions auto-deploy
- §15 — Sanity checklist
- §16 — Common gotchas
- §17 — When to graduate from this setup

> **Start at §0** below right now. Do not jump ahead to MongoDB / domain /
> GitHub Actions until the sections before them are done.

---

## 0. What you need before starting

- AWS account (free tier eligible)
- A GitHub account with the `pargig` repo already pushed
  (`https://github.com/parveenjakhar86/pargig.git`)
- A laptop with `ssh` and `git` installed (Windows: use Git Bash or PowerShell;
  Mac/Linux: terminal)
- **FileZilla** installed on your laptop
- Optional: a domain name (any registrar — GoDaddy, Namecheap, Route 53)

---

## 1. Launch an EC2 instance

1. AWS Console → **EC2** → **Launch instance**.
2. **Name:** `pargig-prod`.
3. **AMI:** *Ubuntu Server 22.04 LTS (HVM), SSD Volume Type* — free tier eligible.
   *(24.04 LTS also works — same Canonical publisher.)*
4. **Instance type:** `t3.micro` (free tier).
5. **Key pair:**
   - *Create new key pair* → name `pargig-key`, type RSA, format `.pem`.
   - **Download** `pargig-key.pem` and keep it safe — you can't redownload.
6. **Network settings → Edit:**
   - **VPC:** leave as the default VPC.
   - **Subnet:** pick **No preference** (AWS will auto-pick a default subnet in
     any Availability Zone). The dropdown lists one subnet per AZ
     (e.g. `ap-south-1a`, `ap-south-1b`, `ap-south-1c`) — for a single
     instance the AZ doesn't matter, so don't overthink it.
   - **Auto-assign public IP:** **Enable** *(critical — without this you
     won't get a public IP and can't SSH or reach the API from your phone)*.
   - **Security group: create new**, name `pargig-sg`. Add these inbound rules:

     | Type | Protocol | Port | Source | Why |
     |---|---|---|---|---|
     | SSH | TCP | 22 | My IP | shell access |
     | HTTP | TCP | 80 | Anywhere (0.0.0.0/0) | nginx |
     | HTTPS | TCP | 443 | Anywhere | nginx + TLS |
     | Custom TCP | TCP | 5014 | My IP | (optional) hit backend directly while testing |

     **Don't add MSSQL/1433 even if AWS pre-fills it.** That comes from
     selecting the SQL Server AMI by mistake (see §16). Pargig uses
     MongoDB on Atlas, never SQL Server. If 1433 is in the table, delete
     that row before saving.

     Forgot port 80? Browser will show `ERR_CONNECTION_TIMED_OUT` later.
     You can always edit the security group at AWS → EC2 → Security Groups
     → `pargig-sg` → **Edit inbound rules**.

7. **Storage:** keep default 8 GB gp3. *(Skip S3 Files / EFS / FSx — not needed.)*
8. **Launch instance.**
9. After ~30 sec, click the instance → copy its **Public IPv4 address** and
   **Public IPv4 DNS**. Save both. *(Either works for SSH.)*

---

## 2. SSH into the EC2 box

On your laptop, where `pargig-key.pem` is saved:

```bash
# Mac/Linux/Git Bash
chmod 400 pargig-key.pem
ssh -i pargig-key.pem ubuntu@<EC2_PUBLIC_IP>
```

```powershell
# Windows PowerShell (icacls instead of chmod)
icacls .\pargig-key.pem /inheritance:r
icacls .\pargig-key.pem /grant:r "$($env:USERNAME):(R)"
ssh -i .\pargig-key.pem ubuntu@<EC2_PUBLIC_IP>
```

Replace `<EC2_PUBLIC_IP>` with the actual IP from the EC2 instance page
(e.g. `13.234.56.78`). The first time you connect, type `yes` at the
fingerprint prompt.

You should land at `ubuntu@ip-xxx-xxx:~$`. Everything from here is **on the server**.

> Stopping → starting the EC2 instance reassigns the IP and DNS. If you stop
> the box overnight, update your SSH command, mobile app, and Atlas IP
> whitelist with the new IP next morning. To pin the address forever,
> allocate an **Elastic IP** in EC2 → Network & Security → Elastic IPs →
> Allocate → Associate.

---

## 3. Connect FileZilla (SFTP) for file transfers

FileZilla will be your "drag and drop" tool for moving files between your
laptop and the EC2 box (`.env`, `firebase-service-account.json`, the built
`dist/` folder, the APK, etc.).

EC2 doesn't accept passwords — it only accepts the `.pem` key. FileZilla
needs that key in **PuTTY (`.ppk`)** format, which it imports for you.

1. Open **FileZilla** → menu **Edit → Settings → Connection → SFTP** →
   **Add key file…** → pick your `pargig-key.pem` → FileZilla offers to
   convert it to `pargig-key.ppk` → click **Yes**, save it next to the .pem.
   You'll see it listed under "Public Key Authentication". Click **OK**.
2. Menu **File → Site Manager → New Site** → name it `pargig-prod`. Fill in:
   - **Protocol:** `SFTP - SSH File Transfer Protocol`
   - **Host:** `<EC2_PUBLIC_IP>`
   - **Port:** `22`
   - **Logon Type:** `Key file`
   - **User:** `ubuntu`
   - **Key file:** browse to `pargig-key.ppk` (or `.pem` — FileZilla accepts
     both since you imported it)
3. Click **Connect** → accept the host key fingerprint the first time.
4. The right pane is the EC2 server. Navigate to `/home/ubuntu/` (the
   default home) — that's where the repo will live after `git clone`.

**Tip:** the *Quick connect* bar across the top can also be used:
host `sftp://<EC2_PUBLIC_IP>`, user `ubuntu`, leave password blank, port `22`
— FileZilla picks up the key from Settings.

If you ever see "**Server unexpectedly closed network connection**", double
check (a) the EC2 security group has port 22 open from your IP, and (b) the
key is loaded under Settings → SFTP, not just attached to the site.

---

## 4. Server base setup

Run these on the EC2 box (the SSH session from §2). This installs everything
the project needs.

```bash
sudo apt update && sudo apt -y upgrade

# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt -y install nodejs

# Git, build tools, Nginx
sudo apt -y install git build-essential nginx

# PM2 (keeps backend running + auto-restart on crash/reboot)
sudo npm install -g pm2

# Verify
node -v   # should be v20.x
npm -v
git --version
nginx -v
pm2 -v
```

If every version prints, the server is ready. **Do not skip this section** —
the rest of the guide assumes all five tools are installed.

---

## 5. Create a MongoDB Atlas cluster (free)

The backend needs MongoDB. Running Mongo on the same EC2 micro instance is
possible but eats RAM. Atlas gives you 512 MB free forever.

1. Sign up at <https://www.mongodb.com/cloud/atlas/register>.
2. **Create a Cluster** → choose **M0 (Free)** → AWS → region near your EC2
   (`ap-south-1` if your EC2 is in Mumbai).
3. **Database Access** → *Add new database user* → username `pargig`, generate
   a strong password, save it somewhere safe.
4. **Network Access** → *Add IP Address* → click **Add Current IP Address**
   AND add the **EC2 public IP** as a separate entry. *(Avoid `0.0.0.0/0` —
   that allows the world to attempt logins.)*
5. **Database** → *Connect* → *Drivers* → copy the connection string. It looks
   like:

   ```
   mongodb+srv://pargig:<password>@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```

   You'll paste this into `.env` as `MONGO_URI` in §7. Replace `<password>` with
   the real password and add the database name `pargig` before the `?`, like:
   `mongodb+srv://pargig:PASS@cluster0.xxxxx.mongodb.net/pargig?retryWrites=true&w=majority`.

---

## 6. Clone the repo onto EC2

You can use HTTPS (simpler) or SSH (better long-term).

### Option A — HTTPS (start with this)

```bash
cd ~
git clone https://github.com/parveenjakhar86/pargig.git
cd pargig
ls
# you should see backend/, frontend/, mobile/, DEPLOY.md, etc.
```

If your repo is **private**, GitHub will ask for username + a *personal access
token* (Settings → Developer settings → Tokens). Paste the token as the password.

### Option B — SSH (for hands-free `git pull` later)

On the EC2 box:

```bash
ssh-keygen -t ed25519 -C "pargig-ec2"
# accept defaults, no passphrase
cat ~/.ssh/id_ed25519.pub
```

Copy the printed key. On GitHub → Settings → SSH and GPG keys → *New SSH key*
→ paste. Then on EC2:

```bash
cd ~
git clone git@github.com:parveenjakhar86/pargig.git
cd pargig
```

---

## 7. Backend `.env` and Firebase service account

These files are gitignored — they don't come down with `git clone`. You
upload them with **FileZilla** and (for `.env`) tweak the values.

### 7a. Generate a JWT secret first (on EC2 SSH)

```bash
openssl rand -hex 32
```

Copy the long hex string — you'll paste it into `.env` as `JWT_SECRET=` in a
moment.

### 7b. Edit `.env` on your laptop, then upload via FileZilla

On your **laptop**, open `backend/.env.example`. Copy it to `backend/.env`
(keep the `.example` file intact) and fill in real values:

```bash
PORT=5014
MONGO_URI=mongodb+srv://pargig:PASS@cluster0.xxxxx.mongodb.net/pargig?retryWrites=true&w=majority
JWT_SECRET=<paste the openssl output>
WALLET_DEPOSIT_AMOUNT=20
FIRST_JOB_FREE_BELOW=1000
# any other keys your .env.example lists
```

Save the file.

In **FileZilla** (already connected to EC2 from §3):

1. **Left pane (laptop):** browse to your local `pargig/backend/` folder.
2. **Right pane (server):** browse to `/home/ubuntu/pargig/backend/`.
3. Drag `backend/.env` from left → right. FileZilla uploads it.
4. Drag `backend/firebase-service-account.json` the same way.

> If you don't see hidden files like `.env`: in FileZilla menu **Server →
> Force showing hidden files**.

### 7c. Lock down permissions (on EC2 SSH)

```bash
chmod 600 ~/pargig/backend/.env
chmod 600 ~/pargig/backend/firebase-service-account.json
ls -l ~/pargig/backend/.env ~/pargig/backend/firebase-service-account.json
# both lines should start with -rw------- (owner read/write only)
```

> Updating these later? Edit on your laptop, drop the new file on the right
> pane in FileZilla — it overwrites — then `pm2 restart pargig-api` so the
> backend reloads `.env`.

---

## 8. Install backend deps and start with PM2

```bash
cd ~/pargig/backend
npm ci --omit=dev   # production install
# Smoke test
node server.js
# you should see "Mongo connected" and "API on :5014". Ctrl+C to stop.

# Run under PM2
pm2 start server.js --name pargig-api
pm2 save
pm2 startup systemd
# the command pm2 prints back — copy and run it (it adds a systemd unit so PM2
# starts automatically after every reboot).

pm2 status
pm2 logs pargig-api --lines 50
```

Quick sanity test (still on EC2):

```bash
curl -s http://localhost:5014/api
# → "Pargig API …"
```

---

## 9. Nginx reverse proxy

We'll route `/api/*` to the Node backend and serve the admin frontend at `/`.

```bash
sudo nano /etc/nginx/sites-available/pargig
```

Paste:

```nginx
server {
    listen 80;
    server_name _;     # accept any host — replace with your domain later
    client_max_body_size 25M;   # photo uploads

    # Admin frontend (built static files)
    root /var/www/pargig-admin;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:5014/api/;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # User-uploaded photos
    location /uploads/ {
        proxy_pass http://127.0.0.1:5014/uploads/;
    }
}
```

Enable it and reload:

```bash
sudo ln -s /etc/nginx/sites-available/pargig /etc/nginx/sites-enabled/pargig
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t                # config check
sudo systemctl reload nginx
```

In your browser visit `http://<EC2_PUBLIC_IP>/api` — you should see the
"Pargig API" string. The site root will 404 until §10 builds the frontend.

---

## 10. Build & deploy the admin frontend

> ### ⚠️ Pre-flight checklist — verify these BEFORE you build
>
> Skipping this caused 2+ hours of "blank page" debugging on the last
> deploy. Spend 60 seconds here and save yourself the pain.
>
> **1. `vite.config.js` — `base:` must match the URL path you'll serve from.**
> If you'll open the admin at `http://IP/`, set:
> ```js
> // No base line at all (defaults to '/')
> ```
> If you'll serve at `http://IP/admin/`, set `base: '/admin/'` AND
> configure Nginx to match. **Don't mismatch them.**
>
> **2. `src/main.jsx` — `<BrowserRouter basename>` must match `vite.config.js` base.**
> Both `/admin/` or both unset. A mismatch = blank page (router can't find
> any route).
>
> **3. `src/api.js` (or wherever axios/fetch is configured) — base URL must be `/api`, not `http://localhost:5014`.**
> Example:
> ```js
> const baseURL = '/api'           // ✅ works in dev (proxy) AND prod (Nginx)
> // const baseURL = 'http://localhost:5014/api'   // ❌ only works in dev
> ```
>
> **4. Hard-coded redirects** (e.g. `location.assign('/admin/login')` in
> 401 handlers) **must match your basename**. If you removed `basename`,
> change to `/login`.
>
> **5. After every source change, ALWAYS:**
> - Save the file (Ctrl+S)
> - Run `npm run build` (the rebuild reads from disk, not memory)
> - Verify the bundle:
>   ```powershell
>   # On Windows / PowerShell
>   Select-String -Path dist\assets\*.js -Pattern "localhost:5014"
>   # Expected: nothing. If it prints lines, your edits didn't save before build.
>   ```
> - Look at `dist\index.html` — `<script src="...">` should match what you
>   set in `vite.config.js`'s `base`.
>
> **6. Wipe the server folder before each upload.** `dist/` filenames have
> hashes that change every build. Mixing old + new files causes the browser
> to ask for a JS file that no longer exists, Nginx falls back to
> `index.html`, browser sees HTML where it expected JS → blank page +
> `Failed to load module script: MIME type "text/html"` in console.
> ```bash
> sudo rm -rf /var/www/admin-frontend/*
> ```

Two options. **Pick one.**

### Option A — Build on EC2 (one-machine, simpler)

```bash
sudo mkdir -p /var/www/pargig-admin
sudo chown -R ubuntu:ubuntu /var/www/pargig-admin

cd ~/pargig/frontend
npm ci
npm run build
cp -r dist/* /var/www/pargig-admin/
```

If `npm run build` runs out of memory on the free-tier t3.micro, see the
swap-file fix in §16 (or use Option B).

### Option B — Build on your laptop, upload `dist/` via FileZilla (recommended)

Saves the EC2 box from running Vite/webpack and keeps the upload to a few
hundred KB of static files.

**On EC2 (one-time):** create the destination folder and give your user
ownership:

```bash
sudo mkdir -p /var/www/pargig-admin
sudo chown -R ubuntu:ubuntu /var/www/pargig-admin
```

**On your laptop:**

```bash
cd frontend
npm ci
npm run build
# produces frontend/dist/
```

In **FileZilla**:

1. Right pane (server): browse to `/var/www/pargig-admin/`.
2. *(Re-deploy only)* Right-click the existing files → **Delete** to clear
   the old build.
3. Left pane (laptop): open `pargig/frontend/dist/`.
4. Select everything inside `dist/` (the files **and** the `assets/`
   subfolder, **not** the `dist/` folder itself) → drag into
   `/var/www/pargig-admin/` on the right.
5. Wait for FileZilla's queue at the bottom to empty.

Visit `http://<EC2_PUBLIC_IP>/` — admin login should render. The frontend
calls `/api/...` which Nginx routes to the backend.

> If your `frontend/src/api.js` hardcodes `http://localhost:5014`, replace it
> with a relative URL `/api` (or use `import.meta.env.VITE_API_BASE`) so the
> built bundle works behind Nginx. Rebuild and re-upload after the change.

---

## 11. Point the mobile app at the new backend

On the phone:

1. Open Pargig.
2. Go to **Server settings** (gear icon on Splash, or `/server` route).
3. Enter `http://<EC2_PUBLIC_IP>` (no `/api` suffix — the app appends it
   itself) or `https://api.example.com` once HTTPS is set up.
4. Tap **Test connection** → should say `Pargig API`.
5. Tap **Save** → re-login.

To distribute the APK, see the bottom of this file (§17a — APK distribution).

---

## 12. (Optional but recommended) Domain + HTTPS

### 12a. DNS

In your registrar, create A records:

| Host | Type | Value |
|---|---|---|
| `api` | A | `<EC2_PUBLIC_IP>` |
| `admin` | A | `<EC2_PUBLIC_IP>` |

Wait 5–30 min for DNS to propagate (`dig api.example.com` should show the IP).

### 12b. Update Nginx

```bash
sudo nano /etc/nginx/sites-available/pargig
```

Replace the single `server_name _;` block with two clean blocks:

```nginx
# Admin
server {
    listen 80;
    server_name admin.example.com;
    root /var/www/pargig-admin;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
}

# API
server {
    listen 80;
    server_name api.example.com;
    client_max_body_size 25M;

    location / {
        proxy_pass http://127.0.0.1:5014;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 12c. Free TLS via Let's Encrypt

```bash
sudo apt -y install certbot python3-certbot-nginx
sudo certbot --nginx -d api.example.com -d admin.example.com
# follow prompts: enter email, agree, choose redirect HTTP → HTTPS
```

Certbot rewrites the Nginx config to add 443 blocks and sets up a cron timer
that auto-renews every 60 days.

Update the mobile app's "Server settings" to `https://api.example.com`.

---

## 13. After-deploy update workflow (when you change code)

The first deploy is done. From now on, every code change follows one of
the playbooks below. Pick the section that matches what you changed.

> **Two terminals you'll keep open:**
> - **PowerShell** on your laptop — for `git push`, `npm run build`
> - **SSH session** to EC2 (`ubuntu@ip-...`) — for `git pull`, `pm2`, `chown`
>
> Plus **FileZilla** for any file transfers.

---

### 13a. Backend code change (controllers, models, routes, server.js, etc.)

**On your laptop (PowerShell):**

```powershell
cd E:\node\pargig
git add .
git commit -m "fix: <describe change>"
git push origin main
```

**On EC2 (SSH):**

```bash
cd ~/pargig
git pull
cd ~/pargig/backend
npm ci --omit=dev      # only if package.json changed; safe to skip otherwise
pm2 restart pargig-api
pm2 logs pargig-api --lines 20 --nostream     # verify clean startup
```

**Nginx reload? ❌ No.** Nginx isn't involved — it just proxies to PM2.

**Verify on browser/laptop:**
```
http://3.111.246.106/api    # should still print "Pargig API"
```

Tail logs while you test the change:
```bash
pm2 logs pargig-api
# Ctrl+C to exit
```

---

### 13b. Backend `.env` change (DB URL, JWT secret, Firebase keys)

`.env` is gitignored, so it can't go through `git push`. Edit on your
**laptop**, upload via **FileZilla**, then restart PM2.

**On laptop:**
1. Open `E:\node\pargig\backend\.env` in your editor, change values, save.

**In FileZilla:**
1. Right pane: `/home/ubuntu/pargig/backend/`
2. Left pane: `E:\node\pargig\backend\`
3. Drag `.env` from left to right (it overwrites). Same for
   `firebase-service-account.json` if that changed.

**On EC2:**

```bash
chmod 600 ~/pargig/backend/.env
chmod 600 ~/pargig/backend/firebase-service-account.json
pm2 restart pargig-api
pm2 logs pargig-api --lines 20 --nostream
```

**Nginx reload? ❌ No.**

---

### 13c. Admin frontend code change (any `*.jsx`, `*.css`, etc.)

Frontend must be **rebuilt** on your laptop and the `dist/*` re-uploaded.

**On laptop:**

```powershell
cd E:\node\pargig\admin-frontend
git pull                        # if you committed via git
npm ci                          # only if package.json changed
npm run build
```

Wait for `✓ built in X.XXs`.

**Verify the build is clean** (catches the bugs we hit on the first deploy):

```powershell
# Should print NOTHING (no leftover localhost:5014)
Select-String -Path dist\assets\*.js -Pattern "localhost:5014"

# Should reference /assets/... (NOT /admin/assets/...)
Get-Content dist\index.html | Select-String "src="
```

**On EC2 — wipe before re-upload (critical):**

```bash
sudo rm -rf /var/www/admin-frontend/*
sudo rm -rf /var/www/admin-frontend/.??*  2>/dev/null
ls /var/www/admin-frontend/      # must be empty
```

> Why wipe? Vite gives every build new hashed filenames
> (`index-aB3fG2H1.js`). If old + new files coexist, the freshly written
> `index.html` references new hashes that exist, but old `assets/*` files
> may also be there. Worst case: a partial drag leaves `index.html` from
> build N pointing at JS from build N-1 → blank page + "MIME type
> text/html" error.

**In FileZilla:**

1. Right pane (server): `/var/www/admin-frontend/` (now empty)
2. Left pane (laptop): open inside `E:\node\pargig\admin-frontend\dist\`
   so you see `index.html`, `assets`, etc. directly
3. Click in left pane → **Ctrl+A** → drag everything to right pane
4. Wait for transfer queue to show "0 failed"

**On EC2 — fix permissions:**

```bash
sudo chown -R ubuntu:ubuntu /var/www/admin-frontend
sudo chmod -R 755 /var/www/admin-frontend
ls /var/www/admin-frontend/      # expected: assets  index.html  ...
```

**Browser test (Incognito to dodge cache):**

Open Ctrl+Shift+N → `http://3.111.246.106/`. Hard-refresh (Ctrl+Shift+R)
if needed.

**Nginx reload? ❌ No.** Nginx serves files from disk on every request —
swapping the files in `/var/www/admin-frontend/` is enough.

---

### 13d. Both backend and frontend changed

Run §13a (backend), then §13c (frontend). Or in this concise sequence:

**On laptop:**

```powershell
# 1. Build admin frontend
cd E:\node\pargig\admin-frontend
npm run build

# 2. Push backend code to GitHub
cd E:\node\pargig
git add .
git commit -m "feat: <change>"
git push origin main
```

**On EC2:**

```bash
# Backend
cd ~/pargig
git pull
cd ~/pargig/backend
npm ci --omit=dev
pm2 restart pargig-api

# Frontend folder wipe
sudo rm -rf /var/www/admin-frontend/*
```

**FileZilla:** drag `dist\*` → `/var/www/admin-frontend/`.

**On EC2 again:**

```bash
sudo chown -R ubuntu:ubuntu /var/www/admin-frontend
sudo chmod -R 755 /var/www/admin-frontend
pm2 logs pargig-api --lines 10 --nostream
```

**Nginx reload? ❌ No.** Neither change touches `/etc/nginx/...`.

---

### 13e. Mobile app code change

Mobile is **only** rebuilt on your laptop into a new APK. The EC2 server
has nothing to do here.

**On laptop:**

```powershell
cd E:\node\pargig\mobile
flutter build apk --release
# output: mobile\build\app\outputs\flutter-apk\app-release.apk
```

Distribute the new APK to users via WhatsApp / Drive / your admin
download page.

**Nginx reload? ❌ No.** **PM2 restart? ❌ No.**

---

### 13f. Nginx config change (`/etc/nginx/sites-available/pargig`)

This is the **only** scenario where Nginx needs reloading.

```bash
sudo nano /etc/nginx/sites-available/pargig
# (edit + save)

sudo nginx -t                              # validate (must say "test is successful")
sudo systemctl reload nginx                # apply
```

**PM2 restart? ❌ No.**

---

### 13g. Quick-reference: "do I need to reload Nginx?"

| What changed | Nginx reload? | PM2 restart? | Build? |
|---|---|---|---|
| Backend `.js` code | ❌ | ✅ | ❌ |
| Backend `.env` / Firebase JSON | ❌ | ✅ | ❌ |
| Backend `package.json` | ❌ | ✅ (after `npm ci`) | ❌ |
| Frontend `.jsx` / `.css` / `.js` source | ❌ | ❌ | ✅ `npm run build` |
| Frontend `vite.config.js` | ❌ | ❌ | ✅ `npm run build` |
| Frontend `package.json` | ❌ | ❌ | ✅ (`npm ci` then `npm run build`) |
| Mobile Flutter source | ❌ | ❌ | ✅ `flutter build apk --release` |
| `/etc/nginx/sites-available/pargig` | ✅ | ❌ | ❌ |
| TLS cert (certbot auto-handles) | (auto) | ❌ | ❌ |

Rule of thumb: **Nginx only reloads when its own config file changes.**
Files in `/var/www/admin-frontend/` are read fresh on every request.

---

### 13h. Optional: deploy script for the backend half

Stick this on EC2 once so backend deploys are a single command.

```bash
nano ~/deploy.sh
```

Paste:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/pargig
git pull --ff-only

cd ~/pargig/backend
npm ci --omit=dev
pm2 restart pargig-api

echo "Backend deployed."
```

```bash
chmod +x ~/deploy.sh
```

After every backend `git push`, from your **laptop**:

```powershell
ssh -i pargig-key.pem ubuntu@3.111.246.106 "~/deploy.sh"
```

Frontend still goes through the build + FileZilla flow in §13c — the
script doesn't touch it.

---

### 13i. (Alternative) Have the script do the frontend too

If your EC2 has enough RAM to build (or you've added swap from §16),
append these lines to `~/deploy.sh`:

```bash
# Frontend (only if you want to build on the server)
cd ~/pargig/admin-frontend
npm ci
npm run build
sudo rm -rf /var/www/admin-frontend/*
cp -r dist/* /var/www/admin-frontend/
sudo chown -R ubuntu:ubuntu /var/www/admin-frontend
```

---

## 14. (Optional) Auto-deploy from GitHub Actions

So `git push` alone deploys, no SSH step needed.

1. **On EC2**, run `cat ~/.ssh/authorized_keys` — it should already have your
   laptop's key. Generate a *deploy* key:

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/gh-actions -N ""
   cat ~/.ssh/gh-actions.pub >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   cat ~/.ssh/gh-actions   # copy this private key
   ```

2. **On GitHub** → repo → Settings → Secrets and variables → Actions → New
   secret. Add three:

   | Name | Value |
   |---|---|
   | `EC2_HOST` | `<EC2_PUBLIC_IP>` |
   | `EC2_USER` | `ubuntu` |
   | `EC2_SSH_KEY` | the private key text from `~/.ssh/gh-actions` |

3. **In the repo**, create `.github/workflows/deploy.yml`:

   ```yaml
   name: Deploy

   on:
     push:
       branches: [main]

   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: appleboy/ssh-action@v1.0.3
           with:
             host: ${{ secrets.EC2_HOST }}
             username: ${{ secrets.EC2_USER }}
             key: ${{ secrets.EC2_SSH_KEY }}
             script: ~/deploy.sh
   ```

   Commit + push. Now every push to `main` runs `~/deploy.sh` on the box.

---

## 15. Sanity checklist

- [ ] `pm2 status` shows `pargig-api` as **online**.
- [ ] `curl https://api.example.com/api` returns the Pargig API banner.
- [ ] `https://admin.example.com` loads the React admin login.
- [ ] Mobile app, after pointing at the new API, can log in and post a job.
- [ ] Photos uploaded from the app load via `https://api.example.com/uploads/<file>`.
- [ ] EC2 security group **only allows SSH from your IP** (not `0.0.0.0/0`).
- [ ] Atlas network access is locked to the EC2 IP, not `0.0.0.0/0`.
- [ ] `.env` and `firebase-service-account.json` exist on the server but are
      not in git.

---

## 16. Common gotchas

### Networking

- **`ERR_CONNECTION_TIMED_OUT` in browser** → port 80 not allowed in security
  group. AWS → EC2 → Security Groups → `pargig-sg` → Inbound rules → confirm
  there's a row **HTTP / TCP / 80 / 0.0.0.0/0**. If missing, **Add rule**.
- **Leftover MSSQL / port 1433 rule** in `pargig-sg` → comes from accidentally
  selecting the SQL Server AMI during launch. Delete it — port 1433 wide-open
  is a security risk and you don't run SQL Server.
- **`This site can't be reached` after coming back the next day** → EC2
  stopping/starting reassigns the public IP. Either grab the new IP from the
  AWS console (and update mobile app + Atlas whitelist), or allocate an
  **Elastic IP** in EC2 → Elastic IPs → Allocate → Associate to make it
  permanent (free while attached to a running instance).
- **`Test-NetConnection IP -Port 80` returns False** but SSH works → port 80
  blocked in security group, OR Ubuntu's `ufw` is active (`sudo ufw status`,
  add `sudo ufw allow 80,443/tcp` if so), OR Nginx isn't actually listening
  (`sudo ss -tlnp \| grep :80`).

### Backend / PM2

- **502 Bad Gateway from Nginx** → backend isn't running. `pm2 logs pargig-api`.
- **`Mongo connection error`** → wrong password in `MONGO_URI`, or Atlas IP
  whitelist doesn't include the EC2 public IP. URL-encode special chars in
  passwords: `@` → `%40`, `#` → `%23`, `/` → `%2F`.
- **`EADDRINUSE :::5014`** → an old node is still bound to port 5014. The
  most common cause is a leftover *root-owned* PM2 daemon from a previous
  `sudo pm2 …` mistake. Fix:
  ```bash
  sudo pkill -9 -f "node.*server.js"
  sudo pkill -9 -f PM2
  pm2 kill 2>/dev/null
  cd ~/pargig/backend
  pm2 start server.js --name pargig-api
  ```
- **`PM2 ERROR: Permission denied … rpc.sock`** → PM2 was started as root,
  leaving `~/.pm2/` root-owned. Fix:
  ```bash
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.pm2
  pm2 kill && pm2 start server.js --name pargig-api
  ```
  **Rule:** never `sudo pm2 …`. PM2 always runs as `ubuntu`. The only sudo
  PM2 line is the one `pm2 startup systemd` prints back at you.
- **`PM2: pargig-api errored, restart counter keeps climbing`** → the app
  itself crashes on startup. `pm2 logs pargig-api --lines 50 --nostream`
  shows the real error (Mongo auth, missing env, missing module, etc.).

### Frontend (Vite/React) — most "blank page" causes

- **Blank white page, console says `Failed to load module script: MIME type
  "text/html"`** → `index.html` is asking for a JS file Nginx can't find,
  and Nginx's `try_files … /index.html` falls back to serving HTML. Two
  causes:
    1. `vite.config.js` has `base: '/admin/'` but Nginx serves at `/` →
       remove the `base:` line, rebuild.
    2. Hash mismatch: old `index.html` left over with new `assets/`. Always
       wipe `/var/www/admin-frontend/*` before re-uploading.
- **Blank page, console clean, but no UI** → `<BrowserRouter basename="/admin">`
  in `main.jsx` while opening `http://IP/`. The router can't match any route
  outside its basename → renders nothing. Either remove the basename, or
  serve at `http://IP/admin/`.
- **Console: `ERR_CONNECTION_REFUSED` for `http://localhost:5014/api/...`** →
  the bundled JS still calls localhost. In `src/api.js` (or wherever) change
  `'http://localhost:5014/api'` → `'/api'`. Save, **rebuild**, re-upload.
  Verify before upload:
  ```powershell
  Select-String -Path dist\assets\*.js -Pattern "localhost:5014"
  # Should print nothing.
  ```
- **`vite.config.js` `base:` and `BrowserRouter basename=` mismatch** →
  always blank. Either both `'/admin/'` (and Nginx serves at `/admin/`) or
  both unset (and Nginx serves at `/`).
- **Browser keeps showing old broken version** → cache. Always test in
  **Incognito** (Ctrl+Shift+N) after a frontend deploy. Or hard-refresh
  with **Ctrl+Shift+R**.
- **Photos upload but don't display** → frontend or mobile is hitting
  `http://EC2_IP/uploads/...` while the page is on HTTPS. Use relative paths
  or the same `https://api.example.com/uploads/...` host.

### Build / disk / ops

- **Disk fills up** → `pm2 logs` keep growing. Run `pm2 install pm2-logrotate`
  once.
- **Free tier EC2 OOM during `npm run build`** → temporarily add a 1 GB swap
  (or skip — build on the laptop and FileZilla `dist/` instead, see §10
  Option B):
  ```bash
  sudo fallocate -l 1G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  ```
- **Wrong AMI picked at launch** → if you accidentally chose a Marketplace
  AMI like "Microsoft SQL Server on Ubuntu", **terminate** that instance
  (top right → Instance state → Terminate) and launch a fresh one with the
  Quick-Start Canonical Ubuntu AMI from §1.
- **`fatal: destination path 'pargig' already exists and is not an empty
  directory`** → an earlier `git clone` partial-failed and left an empty
  folder. Fix: `rm -rf ~/pargig` then re-clone.
- **`sudo: command not found` (sudo, apt, npm, pm2 …)** → you're running
  Linux commands from the **Windows Command Prompt** or PowerShell. Those
  only exist on the EC2 box. SSH in first; the prompt must be
  `ubuntu@ip-xxx:~$` before any of those work.

### File ownership rules

| Path | Owner |
|---|---|
| `/home/ubuntu/pargig` and everything under it | `ubuntu:ubuntu` |
| `/home/ubuntu/.pm2` | `ubuntu:ubuntu` |
| `/var/www/admin-frontend` | `ubuntu:ubuntu` |
| `/etc/nginx/...` | `root:root` (edited via `sudo`) |
| `/usr/bin/node`, `/usr/bin/git`, `/usr/sbin/nginx` | `root:root` (system) |

When in doubt: `sudo chown -R ubuntu:ubuntu <path>` for any app/code path,
never for system paths.

---

## 17. Sudo commands cheat sheet (everything we ran on this deploy)

Every `sudo` command you'll touch during a Pargig deploy, grouped by what
it does. Run all of these on the **EC2 box** (after `ssh ubuntu@…`), never
on your laptop.

### Server bootstrap (once per fresh EC2 box)

```bash
# System updates
sudo apt update && sudo apt -y upgrade

# Node.js 20 LTS via NodeSource (do NOT use plain `apt install nodejs` —
# Ubuntu 22.04 ships an older Node)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt -y install nodejs

# Other tools
sudo apt -y install git build-essential nginx curl

# PM2 globally — only `npm install -g` uses sudo, never `sudo pm2 …` later
sudo npm install -g pm2
```

### Nginx setup

```bash
# Edit the site config
sudo nano /etc/nginx/sites-available/pargig

# Enable it + remove default
sudo ln -s /etc/nginx/sites-available/pargig /etc/nginx/sites-enabled/pargig
sudo rm -f /etc/nginx/sites-enabled/default

# Validate config (always run before reloading)
sudo nginx -t

# Apply changes (only after a config edit — NOT needed when you swap files
# in /var/www/admin-frontend/)
sudo systemctl reload nginx

# If nginx isn't running at all
sudo systemctl start nginx
sudo systemctl status nginx --no-pager | head -10
```

### Frontend folder (`/var/www/admin-frontend`)

```bash
# Create the folder (one-time)
sudo mkdir -p /var/www/admin-frontend

# Wipe before each upload of dist/* (avoids hash-mismatch blank-page bug)
sudo rm -rf /var/www/admin-frontend/*
sudo rm -rf /var/www/admin-frontend/.??*    # also clears hidden files

# After every upload, set owner + permissions
sudo chown -R ubuntu:ubuntu /var/www/admin-frontend
sudo chmod -R 755 /var/www/admin-frontend

# If Nginx 403s the JS files (rare, but if /var/www has restrictive perms)
sudo chmod o+x /var/www
sudo chmod o+x /var/www/admin-frontend

# Test as Nginx user — should print JS, not "Permission denied"
sudo -u www-data cat /var/www/admin-frontend/assets/index-*.js | head -1

# Trace permissions all the way up a path (when debugging 403)
sudo namei -l /var/www/admin-frontend/assets/index-1msU6HXn.js
```

### Backend (`~/pargig/backend`)

```bash
# Re-take ownership of the project folder (if you ever cloned/edited as root)
sudo chown -R ubuntu:ubuntu /home/ubuntu/pargig

# Lock down secrets after upload
chmod 600 ~/pargig/backend/.env
chmod 600 ~/pargig/backend/firebase-service-account.json

# (these two don't need sudo if the file is already ubuntu-owned)
```

### PM2 — fixing common breakage

```bash
# Re-take ownership of PM2 state (if PM2 was started as root by mistake)
sudo chown -R ubuntu:ubuntu /home/ubuntu/.pm2

# Kill rogue Node / PM2 processes that hold port 5014 (EADDRINUSE fix)
sudo pkill -9 -f "node.*server.js"
sudo pkill -9 -f PM2

# Find what's using a port
sudo lsof -i :5014
sudo ss -tlnp | grep ':5014 '
sudo ss -tlnp | grep ':80 '

# Then (as ubuntu, no sudo):
pm2 kill
cd ~/pargig/backend
pm2 start server.js --name pargig-api
pm2 save

# Auto-start on reboot — pm2 prints back a sudo command, copy and paste it.
# It looks like:
#   sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu
pm2 startup systemd
```

### Firewall (Ubuntu's `ufw`)

```bash
# Check if active (usually inactive on AWS Ubuntu, security group does the firewalling)
sudo ufw status

# If active and blocking, open the right ports
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload

# Or disable ufw entirely and rely on AWS security groups (safer if you forget):
sudo ufw disable
```

### Diagnostics & debugging

```bash
# Backend reachable locally?
curl -s http://localhost:5014/api

# Through Nginx?
curl -s http://localhost/api

# Built JS served as JS, not HTML? (the MIME-type debug)
curl -I http://localhost/assets/index-XXXX.js

# Look for leftover localhost:5014 in deployed JS (frontend gotcha)
grep -o "localhost:5014" /var/www/admin-frontend/assets/*.js

# Nginx error log
sudo tail -50 /var/log/nginx/error.log

# Disk filling up?
df -h
sudo du -sh /home/ubuntu/.pm2/logs
sudo du -sh /home/ubuntu/pargig/backend/uploads
```

### TLS / Let's Encrypt (after you have a domain)

```bash
sudo apt -y install certbot python3-certbot-nginx
sudo certbot --nginx -d api.example.com -d admin.example.com
# certbot edits /etc/nginx/sites-available/pargig itself and reloads.
# Auto-renewal is set up via systemd timer — verify with:
sudo systemctl list-timers | grep certbot
```

### Total reset (start over without re-launching the instance)

```bash
# Kill backend
pm2 delete all
sudo pkill -9 -f "node.*server.js"
sudo pkill -9 -f PM2

# Wipe project folder
rm -rf ~/pargig

# Wipe frontend
sudo rm -rf /var/www/admin-frontend/*

# Stop nginx (so port 80 is free if you want to debug)
sudo systemctl stop nginx
```

Then re-clone, redo §6 onwards. The EC2 box, MongoDB Atlas, and security
groups stay as-is.

---

## 18. When to graduate from this setup

This is enough for early users. You'll outgrow it when:

- You need **zero-downtime** deploys → add a second EC2 + ALB, or move backend
  to **ECS Fargate** behind an ALB.
- Photo storage outpaces EBS → move uploads from `backend/uploads/` to **S3**,
  serve via **CloudFront**.
- You want a **CDN** for the admin → push the built `dist/` to **S3 +
  CloudFront** instead of Nginx.
- Traffic grows → upgrade Atlas to M10+ and EC2 to `t3.small`/`t3.medium`.

None of this is needed on day one.

### 17a. APK distribution (bonus)

Build the release APK on your laptop:

```bash
cd mobile
flutter build apk --release
# output: mobile/build/app/outputs/flutter-apk/app-release.apk
```

To make it downloadable from the admin site:

```bash
# On EC2, one-time
mkdir -p /var/www/pargig-admin/downloads
```

In **FileZilla**, drag `app-release.apk` from your laptop into
`/var/www/pargig-admin/downloads/` (rename to `pargig.apk` if you want a
cleaner URL).

To force the browser to download instead of trying to preview, add this
inside the admin Nginx server block:

```nginx
location ~ \.apk$ {
    default_type application/vnd.android.package-archive;
    add_header Content-Disposition 'attachment';
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Share the link `https://admin.example.com/downloads/pargig.apk`. Phones must
have **"Install from unknown sources"** enabled to install a sideloaded APK.
