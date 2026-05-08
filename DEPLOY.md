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

## 0. What you need before starting

- AWS account (free tier eligible)
- A GitHub account with the `pargig` repo already pushed
  (`https://github.com/parveenjakhar86/pargig.git`)
- A laptop with `ssh` and `git` installed (Windows: use Git Bash or PowerShell;
  Mac/Linux: terminal)
- Optional: a domain name (any registrar — GoDaddy, Namecheap, Route 53)

---

## 1. Create a MongoDB Atlas cluster (free)

The backend needs MongoDB. Running Mongo on the same EC2 micro instance is
possible but eats RAM. Atlas gives you 512 MB free forever.

1. Sign up at <https://www.mongodb.com/cloud/atlas/register>.
2. **Create a Cluster** → choose **M0 (Free)** → AWS → region near your EC2.
3. **Database Access** → *Add new database user* → username `pargig`, generate
   a strong password, save it.
4. **Network Access** → *Add IP Address*. For now click **Allow access from
   anywhere** (`0.0.0.0/0`). After EC2 is up, replace this with the EC2 public
   IP for safety.
5. **Database** → *Connect* → *Drivers* → copy the connection string. It looks
   like:

   ```
   mongodb+srv://pargig:<password>@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```

   You'll paste this into `.env` as `MONGO_URI`. Replace `<password>` with the
   real password and add a database name before the `?`, e.g.
   `mongodb+srv://pargig:PASS@cluster0.xxxxx.mongodb.net/pargig?retryWrites=true&w=majority`.

---

## 2. Launch an EC2 instance

1. AWS Console → **EC2** → **Launch instance**.
2. **Name:** `pargig-prod`.
3. **AMI:** *Ubuntu Server 22.04 LTS (HVM), SSD Volume Type* — free tier eligible.
4. **Instance type:** `t3.micro` (free tier).
5. **Key pair:**
   - *Create new key pair* → name `pargig-key`, type RSA, format `.pem`.
   - **Download** `pargig-key.pem` and keep it safe — you can't redownload.
6. **Network settings → Edit:**
   - VPC: default. Subnet: default. **Auto-assign public IP: Enable**.
   - **Security group: create new**, name `pargig-sg`. Add these inbound rules:

     | Type | Protocol | Port | Source | Why |
     |---|---|---|---|---|
     | SSH | TCP | 22 | My IP | shell access |
     | HTTP | TCP | 80 | Anywhere (0.0.0.0/0) | nginx |
     | HTTPS | TCP | 443 | Anywhere | nginx + TLS |
     | Custom TCP | TCP | 5014 | My IP | (optional) hit backend directly while testing |

7. **Storage:** keep default 8 GB gp3.
8. **Launch instance.**
9. After ~30 sec, click the instance → copy its **Public IPv4 address** and
   **Public IPv4 DNS**. Save both.

---

## 3. SSH into the EC2 box

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

You should land at `ubuntu@ip-xxx-xxx:~$`. Everything from here is **on the server**.

---

## 3b. Connect FileZilla (SFTP) for file transfers

FileZilla will be your "drag and drop" tool for moving files between your
laptop and the EC2 box (`.env`, `firebase-service-account.json`, the built
`dist/` folder, etc.).

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

---

## 5. Clone the repo

You can use HTTPS (simpler) or SSH (better long-term).

### Option A — HTTPS (start with this)

```bash
cd ~
git clone https://github.com/parveenjakhar86/pargig.git
cd pargig
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

## 6. Backend `.env` and Firebase service account

These files are gitignored — they don't come down with `git clone`. You
upload them with **FileZilla** and (for `.env`) tweak the values.

### 6a. Generate a JWT secret first (on EC2 SSH)

```bash
openssl rand -hex 32
```

Copy the long hex string — you'll paste it into `.env` as `JWT_SECRET=` in a
moment.

### 6b. Edit `.env` on your laptop, then upload via FileZilla

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

In **FileZilla** (already connected to EC2 from §3b):

1. **Left pane (laptop):** browse to your local `pargig/backend/` folder.
2. **Right pane (server):** browse to `/home/ubuntu/pargig/backend/`.
3. Drag `backend/.env` from left → right. FileZilla uploads it.
4. Drag `backend/firebase-service-account.json` the same way.

> If you don't see hidden files like `.env`: in FileZilla menu **Server →
> Force showing hidden files**.

### 6c. Lock down permissions (on EC2 SSH)

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

## 7. Install backend deps and start with PM2

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

## 8. Nginx reverse proxy

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
"Pargig API" string. The site root will 404 until step 9 builds the frontend.

---

## 9. Build & deploy the admin frontend

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
swap-file fix in §15 (or use Option B).

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

## 10. Point the mobile app at the new backend

On the phone:

1. Open Pargig.
2. Go to **Server settings** (gear icon on Splash, or `/server` route).
3. Enter `http://<EC2_PUBLIC_IP>` (no `/api` suffix — the app appends it
   itself) or `https://api.example.com` once HTTPS is set up.
4. Tap **Test connection** → should say `Pargig API`.
5. Tap **Save** → re-login.

---

## 11. (Optional but recommended) Domain + HTTPS

### 11a. DNS

In your registrar, create A records:

| Host | Type | Value |
|---|---|---|
| `api` | A | `<EC2_PUBLIC_IP>` |
| `admin` | A | `<EC2_PUBLIC_IP>` |

Wait 5–30 min for DNS to propagate (`dig api.example.com` should show the IP).

### 11b. Update Nginx

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

### 11c. Free TLS via Let's Encrypt

```bash
sudo apt -y install certbot python3-certbot-nginx
sudo certbot --nginx -d api.example.com -d admin.example.com
# follow prompts: enter email, agree, choose redirect HTTP → HTTPS
```

Certbot rewrites the Nginx config to add 443 blocks and sets up a cron timer
that auto-renews every 60 days.

Update the mobile app's "Server settings" to `https://api.example.com`.

---

## 12. The deploy workflow (every code change)

The loop after the initial setup is:

1. **You** push to GitHub (`git push origin main`) from your laptop.
2. **EC2** pulls the new code and restarts the backend.
3. **(Frontend only)** Build locally → upload `dist/` via FileZilla.

### 12a. Backend deploy script (one-line on EC2)

Create the script once on EC2:

```bash
nano ~/deploy.sh
```

Paste:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/pargig
git pull --ff-only

# Backend
cd ~/pargig/backend
npm ci --omit=dev
pm2 restart pargig-api

echo "Backend deployed."
```

```bash
chmod +x ~/deploy.sh
```

After every backend change, from your laptop:

```bash
ssh -i pargig-key.pem ubuntu@<EC2_PUBLIC_IP> "~/deploy.sh"
```

(Or just SSH in and run `~/deploy.sh` — same thing.)

### 12b. Frontend deploy via FileZilla (admin changes only)

On your laptop:

```bash
cd frontend
git pull
npm ci
npm run build
```

In **FileZilla**:

1. Right pane (server): `/var/www/pargig-admin/` → select all → **Delete**.
2. Left pane (laptop): open `frontend/dist/` → select all → drag to right.

No backend restart needed — Nginx serves the new files immediately.

### 12c. (Alternative) Build frontend on the server too

If you'd rather have one command do everything (and the EC2 box has enough
RAM, see swap fix in §15), append the frontend lines to `~/deploy.sh`:

```bash
# Frontend (only if you want to build on the server)
cd ~/pargig/frontend
npm ci
npm run build
rm -rf /var/www/pargig-admin/*
cp -r dist/* /var/www/pargig-admin/
```

---

## 13. (Optional) Auto-deploy from GitHub Actions

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

## 14. Sanity checklist

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

## 15. Common gotchas

- **502 Bad Gateway from Nginx** → backend isn't running. `pm2 logs pargig-api`.
- **`Mongo connection error`** → wrong password in `MONGO_URI`, or Atlas IP
  whitelist doesn't include the EC2 public IP.
- **Photos upload but don't display** → frontend or mobile is hitting
  `http://EC2_IP/uploads/...` while the page is on HTTPS. Use relative paths
  or the same `https://api.example.com/uploads/...` host.
- **`EADDRINUSE :::5014`** → an old node is still running. `pm2 list`,
  `pm2 delete <id>`, then `pm2 start server.js --name pargig-api`.
- **Disk fills up** → `pm2 logs` keep growing. Run `pm2 install pm2-logrotate`
  once.
- **Free tier EC2 OOM during `npm run build`** → temporarily add a 1 GB swap:
  ```bash
  sudo fallocate -l 1G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  ```

---

## 16. When to graduate from this setup

This is enough for early users. You'll outgrow it when:

- You need **zero-downtime** deploys → add a second EC2 + ALB, or move backend
  to **ECS Fargate** behind an ALB.
- Photo storage outpaces EBS → move uploads from `backend/uploads/` to **S3**,
  serve via **CloudFront**.
- You want a **CDN** for the admin → push the built `dist/` to **S3 +
  CloudFront** instead of Nginx.
- Traffic grows → upgrade Atlas to M10+ and EC2 to `t3.small`/`t3.medium`.

None of this is needed on day one.
