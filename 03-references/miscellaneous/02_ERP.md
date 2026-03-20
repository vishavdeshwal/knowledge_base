# ERPNext: From-Scratch Setup Guide

## What Is ERPNext?

**ERPNext** is a free, open-source, full-featured **Enterprise Resource Planning (ERP)** system built on top of the **Frappe Framework** — a Python + JavaScript full-stack web framework. You don't just install ERPNext; you install the Frappe ecosystem *first*, then ERPNext sits on top as an "app."

ERPNext handles: Accounting & Finance, HR & Payroll, Inventory & Warehouse, CRM & Sales, Manufacturing, Project Management, Purchase & Supply Chain.

---

## Architecture Overview

```
┌──────────────────────────────────────┐
│            ERPNext App               │  ← Business logic, doctypes, reports
├──────────────────────────────────────┤
│          Frappe Framework            │  ← Web framework, ORM, scheduler
├──────────────────────────────────────┤
│        bench (CLI tool)              │  ← Manages sites, apps, processes
├──────────────────────────────────────┤
│  MariaDB  │  Redis  │  Node.js/yarn  │  ← Data, cache/queue, frontend assets
├──────────────────────────────────────┤
│       Nginx + Supervisor             │  ← Reverse proxy + process manager
├──────────────────────────────────────┤
│         Ubuntu 22.04 LTS             │  ← OS (recommended)
└──────────────────────────────────────┘
```

---

## Components — What They Are & Why Needed

| Component | What It Is | Why ERPNext Needs It |
|---|---|---|
| **Python 3.10+** | Backend language | Frappe is Python-based |
| **pip / venv** | Python package manager + virtual env | Isolates Python deps per bench |
| **Node.js 18+** | JS runtime | Builds frontend assets (Vue/JS) |
| **yarn** | JS package manager | Installs frontend dependencies |
| **MariaDB 10.6+** | Relational database | Stores all ERP data |
| **Redis** | In-memory store | Cache, queue (background jobs), socketio |
| **wkhtmltopdf** | HTML → PDF renderer | Generates print formats / invoices |
| **Nginx** | Reverse proxy | Routes traffic to Frappe gunicorn |
| **Supervisor** | Process manager | Keeps gunicorn, redis-worker, scheduler alive |
| **bench CLI** | Frappe's project manager | Creates sites, installs apps, runs commands |
| **Frappe Framework** | Web framework | ERPNext's foundation |
| **ERPNext App** | The ERP itself | Business modules |

---

## Step 0 — System Requirements

- **OS:** Ubuntu 22.04 LTS (strongly recommended)
- **RAM:** Minimum 4GB (8GB+ for production)
- **CPU:** 2 vCPUs minimum
- **Disk:** 20GB+ free
- **User:** A **non-root sudo user** (bench refuses to run as root)

---

## Step 1 — System Update & Base Packages

**What this does:** Refreshes package lists, upgrades existing packages, installs essential build tools and Git.

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y \
  git curl wget \
  python3 python3-dev python3-pip python3-venv \
  build-essential \
  libffi-dev libssl-dev \
  software-properties-common \
  xvfb libfontconfig \
  cron
```

> `build-essential` provides `gcc`, `make`, etc. — needed to compile Python C extensions.
> `libffi-dev` + `libssl-dev` — required by `cryptography` Python package.
> `xvfb` + `libfontconfig` — required by wkhtmltopdf for headless PDF rendering.

---

## Step 2 — Install MariaDB

**What this does:** Installs the database engine that stores every ERPNext record.

```bash
sudo apt install -y mariadb-server mariadb-client
sudo systemctl start mariadb
sudo systemctl enable mariadb
```

### Secure MariaDB

```bash
sudo mysql_secure_installation
# Set root password, remove anonymous users, disallow remote root login
```

### Configure MariaDB for Frappe

```bash
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

Add/update under `[mysqld]`:

```ini
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
```

```bash
sudo systemctl restart mariadb
```

> **Why utf8mb4?** Frappe stores emoji and multi-byte characters. `utf8` in MySQL only supports 3-byte chars; `utf8mb4` is the true full Unicode set.

---

## Step 3 — Install Redis

**What this does:** Redis serves three roles in Frappe — **cache**, **background job queue**, and **real-time socketio** pub/sub.

```bash
sudo apt install -y redis-server
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

Verify:
```bash
redis-cli ping
# Should return: PONG
```

---

## Step 4 — Install Node.js & yarn

**What this does:** Node.js compiles and bundles frontend JavaScript/CSS assets. yarn manages JS packages.

```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

node -v   # Should be v18.x
npm -v

sudo npm install -g yarn
yarn -v
```

---

## Step 5 — Install wkhtmltopdf

**What this does:** Converts HTML print formats to PDF. Used for invoices, purchase orders, payslips, etc.

```bash
# Always use the patched QT build — the apt version is broken for Frappe
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb

sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -f -y

wkhtmltopdf --version
```

---

## Step 6 — Create a Dedicated System User

**What this does:** bench and Frappe should never run as root. Create a dedicated user.

```bash
sudo adduser frappe
sudo usermod -aG sudo frappe

# Switch to this user for all remaining steps
su - frappe
```

---

## Step 7 — Install bench CLI

**What this does:** `bench` is Frappe's command-line tool. It creates and manages bench environments — a folder containing sites, apps, config, and process scripts. Think of it like Laravel's `artisan` but for the entire environment.

```bash
sudo pip3 install frappe-bench
bench --version
```

---

## Step 8 — Initialize a Bench

**What this does:** Creates a bench directory with a Python virtualenv, installs Frappe framework from GitHub, sets up the folder structure.

```bash
bench init --frappe-branch version-15 ~/frappe-bench
cd ~/frappe-bench
```

**What gets created:**
```
frappe-bench/
├── apps/           ← Frappe and ERPNext app code lives here
│   └── frappe/
├── sites/          ← Each site (database + config) lives here
├── config/         ← Nginx, supervisor, Redis configs
├── env/            ← Python virtualenv
├── logs/           ← Application logs
└── Procfile        ← Process definitions
```

> `--frappe-branch version-15` pins to ERPNext v15 (current stable). Use `version-14` for v14 LTS.

---

## Step 9 — Get ERPNext App

**What this does:** Downloads the ERPNext application code into `apps/erpnext`. It is not yet installed on any site — just downloaded.

```bash
cd ~/frappe-bench
bench get-app --branch version-15 erpnext
```

> This clones `https://github.com/frappe/erpnext` into `apps/erpnext`.

---

## Step 10 — Create a New Site

**What this does:** Creates a new Frappe **site** — a dedicated MariaDB database + config for one ERPNext instance. One bench can host multiple sites (one per client/app).

### About the Site Name

The site name is **just an identifier** — not a live DNS requirement at this stage. It is used as:
- The **folder name** under `sites/`
- The **MariaDB database** identifier
- The **HTTP Host header** Frappe matches incoming requests against

```bash
bench new-site <client-application-name>
# You will be prompted for:
# 1. MariaDB root password (from Step 2)
# 2. Admin password (for ERPNext login)
```

**What this creates:**
```
sites/
└── <client-application-name>/
    ├── site_config.json    ← DB credentials, site settings
    └── private/            ← Uploads, backups
```

### Site Name Options by Scenario

| Scenario | What to pass as site name | DNS Needed? |
|---|---|---|
| Local dev / no domain yet | `<client-application-name>.local` or just `<client-application-name>` | ❌ No |
| Access via IP only | `localhost` | ❌ No |
| Internal network | `<client-application-name>.internal` + `/etc/hosts` entry | ❌ No |
| Real public domain (production) | `erp.<client-application-name>.com` | ✅ Yes — A record |

### If You Want to Rename the Site Later

```bash
# After domain is confirmed
bench rename-site <client-application-name> erp.<client-application-name>.com
```

Or update the hostname in config without renaming:
```bash
# sites/<client-application-name>/site_config.json
{
  "host_name": "https://erp.<client-application-name>.com"
}
```

---

## Step 11 — Install ERPNext on the Site

**What this does:** Runs ERPNext migrations, creates all database tables (doctypes), and links the app to this site.

```bash
bench --site <client-application-name> install-app erpnext
```

> This can take **5–15 minutes** — it creates hundreds of database tables.

---

## Step 12 — Start bench (Development / Verify Mode)

**What this does:** Starts all processes (web server, Redis workers, scheduler) via the Procfile. Good for initial verification.

```bash
bench start
```

Access at: `http://<your-server-ip>:8000`
Login: `Administrator` / *(password set in Step 10)*

---

## Step 13 — Production Setup

For a real server, replace `bench start` with proper Nginx + Supervisor.

### Enable production mode

```bash
sudo bench setup production frappe

# Auto-generates and installs:
# /etc/nginx/conf.d/frappe-bench.conf      ← server_name set to <client-application-name>
# /etc/supervisor/conf.d/frappe-bench.conf ← gunicorn, workers, scheduler
```

### Reload services

```bash
sudo supervisorctl reload
sudo systemctl reload nginx
sudo systemctl enable supervisor nginx
```

### Set default site

```bash
bench use <client-application-name>
```

---

## Step 13a — Nginx Configuration (What Gets Generated)

`bench setup production` auto-generates `/etc/nginx/conf.d/frappe-bench.conf`. Here is what it produces and what each block does:

```nginx
# /etc/nginx/conf.d/frappe-bench.conf

# Upstream block — points Nginx to Frappe's gunicorn process
upstream frappe-<client-application-name> {
    server 127.0.0.1:8000 fail_timeout=0;
}

server {
    listen 80;
    server_name <client-application-name>;   # ← matches your bench site name exactly

    root /home/frappe/frappe-bench/sites;

    # Static assets served directly by Nginx — bypasses gunicorn entirely
    location /assets {
        try_files $uri =404;
    }

    # Site-specific uploaded files
    location ~ ^/files/.*$ {
        root /home/frappe/frappe-bench/sites/<client-application-name>;
        try_files $uri =404;
    }

    # All other requests → forwarded to gunicorn (Frappe app)
    location / {
        proxy_pass http://frappe-<client-application-name>;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### View & Validate After Generation

```bash
# View the generated config
cat /etc/nginx/conf.d/frappe-bench.conf

# Test Nginx config syntax before reloading
sudo nginx -t

# Reload Nginx to apply
sudo systemctl reload nginx
```

> After `certbot --nginx` (Step 15), this file gets updated automatically to add `listen 443 ssl` and certificate paths. Always re-run `sudo nginx -t` after any manual edits.

---

## Step 14 — DNS Setup (When Ready)

When pointing a real domain to this server, add an A record at your DNS provider (Cloudflare, Route53, etc.):

```
Type    Name    Value                   TTL
A       erp     <your-server-public-ip> Auto
```

The `server_name` in Nginx already matches your site name, so no Nginx change is needed.

---

## Step 15 — SSL (Let's Encrypt)

```bash
sudo snap install --classic certbot
sudo certbot --nginx -d erp.<client-application-name>.com
```

---

## Quick Reference — Full Command Sequence

```bash
# 1. System packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget python3 python3-dev python3-pip python3-venv \
  build-essential libffi-dev libssl-dev software-properties-common xvfb libfontconfig cron

# 2. MariaDB
sudo apt install -y mariadb-server mariadb-client
sudo mysql_secure_installation
# Edit /etc/mysql/mariadb.conf.d/50-server.cnf (utf8mb4 settings)
sudo systemctl restart mariadb

# 3. Redis
sudo apt install -y redis-server

# 4. Node.js + yarn
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g yarn

# 5. wkhtmltopdf
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb && sudo apt install -f -y

# 6. Create user
sudo adduser frappe && sudo usermod -aG sudo frappe
su - frappe

# 7. Install bench
sudo pip3 install frappe-bench

# 8. Init bench
bench init --frappe-branch version-15 ~/frappe-bench
cd ~/frappe-bench

# 9. Get ERPNext app
bench get-app --branch version-15 erpnext

# 10. Create site
bench new-site <client-application-name>

# 11. Install ERPNext on site
bench --site <client-application-name> install-app erpnext

# 12. Dev verify
bench start

# 13. Production
sudo bench setup production frappe
bench use <client-application-name>

# 14. SSL (once DNS is pointed)
sudo certbot --nginx -d erp.<client-application-name>.com
```

---

## Optional but Common

| Task | Command |
|---|---|
| Install HRMS module | `bench get-app hrms` → `bench --site <client-application-name> install-app hrms` |
| Backup site | `bench --site <client-application-name> backup` |
| Update all apps | `bench update` |
| Run migrations only | `bench --site <client-application-name> migrate` |
| Add another client site | `bench new-site <another-client-application-name>` |
| Tail logs | `tail -f ~/frappe-bench/logs/*.log` |