#!/bin/bash
# ==============================================================================
# ERPNext v16 Automated Installation Script
# Supports: Local (All-in-one) and Managed (Remote DB/Redis) Deployments
# Supports: amd64 and arm64 architectures
# Idempotent: Safe to re-run — skips already-completed steps
# ==============================================================================

set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[x] $1${NC}"; exit 1; }
skip() { echo -e "${CYAN}[~] SKIP: $1${NC}"; }

# ==============================================================================
# 1. Interactive Prompts
# ==============================================================================
clear
echo "================================================================="
echo "          ERPNext v16 Automated Setup Script"
echo "          (Idempotent — safe to re-run)"
echo "================================================================="
echo ""
echo "Select Architecture Type:"
echo "  1) Local   (MariaDB and Redis installed on this VM)"
echo "  2) Managed (MariaDB and Redis are hosted remotely/managed)"
echo ""
read -p "Enter choice [1 or 2]: " ARCH_CHOICE

if [[ "$ARCH_CHOICE" != "1" && "$ARCH_CHOICE" != "2" ]]; then
    err "Invalid choice. Exiting."
fi

read -p "Client Application / Site Name (e.g., zippee-erp): " SITE_NAME
read -s -p "Database Root Password: " DB_ROOT_PASS; echo ""
read -s -p "ERPNext Admin Password: " ADMIN_PASS; echo ""
read -p "Domain Name for ERP (e.g., erp.domain.com) [Optional, press Enter to skip]: " DOMAIN_NAME

ENABLE_SSL=""
SSL_EMAIL=""
if [ -n "$DOMAIN_NAME" ]; then
    read -p "Enable Let's Encrypt SSL? (Type 'n' if using AWS ALB/Cloudflare) [y/N]: " ENABLE_SSL
    if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
        read -p "Email for Let's Encrypt SSL: " SSL_EMAIL
    fi
fi

read -p "Install extra apps (HRMS, Insights, India Compliance)? [y/N]: " INSTALL_EXTRA_APPS

MARIADB_IP="127.0.0.1"
REDIS_IP=""
if [ "$ARCH_CHOICE" == "2" ]; then
    SETUP_TYPE="managed"
    read -p "Remote MariaDB Private IP: " MARIADB_IP
    read -p "Managed Redis IP: " REDIS_IP
    if [[ -z "$MARIADB_IP" || -z "$REDIS_IP" ]]; then
        err "Remote IPs cannot be empty for Managed setup."
    fi
else
    SETUP_TYPE="local"
fi

# Validate required fields
[ -z "$SITE_NAME" ]    && err "Site name cannot be empty."
[ -z "$DB_ROOT_PASS" ] && err "Database root password cannot be empty."
[ -z "$ADMIN_PASS" ]   && err "Admin password cannot be empty."

echo ""
echo "================================================================="
echo "Review Configuration:"
echo "Architecture:   $SETUP_TYPE"
echo "Site Name:      $SITE_NAME"
[ "$SETUP_TYPE" == "managed" ] && echo "MariaDB IP:     $MARIADB_IP"
[ "$SETUP_TYPE" == "managed" ] && echo "Redis IP:       $REDIS_IP"
echo "Domain:         ${DOMAIN_NAME:-None}"
echo "Extra Apps:     ${INSTALL_EXTRA_APPS:-N}"
echo "================================================================="
read -p "Press Enter to start installation or Ctrl+C to cancel..."

# ==============================================================================
# 2. Detect Architecture
# ==============================================================================
SYS_ARCH=$(dpkg --print-architecture)
log "System architecture: $SYS_ARCH"

# ==============================================================================
# Detect Public IP
# Used as server_name fallback when no domain is provided, so the site is
# accessible via http://<public-ip> without needing a domain name.
# ==============================================================================
log "Detecting public IP..."
PUBLIC_IP=$(curl -sf --max-time 5 http://checkip.amazonaws.com \
    || curl -sf --max-time 5 https://api.ipify.org \
    || curl -sf --max-time 5 https://ifconfig.me \
    || echo "")
if [ -n "$PUBLIC_IP" ]; then
    log "Public IP detected: $PUBLIC_IP"
else
    warn "Could not detect public IP — will use '_' as server_name (nginx catch-all)."
    PUBLIC_IP="_"
fi

# Determine effective server identity for nginx server_name
# Priority: domain (if provided) > public IP > catch-all
SERVER_IDENTITY="${DOMAIN_NAME:-$PUBLIC_IP}"
log "Nginx server_name will be set to: $SERVER_IDENTITY"

# ==============================================================================
# 3. Swap
# ==============================================================================
SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')
if [ "$SWAP_MB" -lt 2000 ]; then
    if [ ! -f /swapfile ]; then
        log "Creating 2GB swap file..."
        sudo fallocate -l 2G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
    fi
    sudo swapon /swapfile 2>/dev/null || true
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    log "Swap enabled."
else
    skip "Swap already sufficient (${SWAP_MB}MB)."
fi

# ==============================================================================
# 4. Base System Packages
# ==============================================================================
log "Updating apt and installing base packages..."
sudo apt update -qq
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt install -y \
    git curl wget jq \
    python3 python3-dev python3-pip python3-venv \
    build-essential \
    libffi-dev libssl-dev \
    software-properties-common \
    xvfb libfontconfig \
    cron nginx supervisor pkg-config \
    libmariadb-dev libmariadb-dev-compat \
    mysql-client redis-tools

# ==============================================================================
# 5. Python 3.14
# ==============================================================================
if python3.14 --version >/dev/null 2>&1; then
    skip "Python 3.14 already installed ($(python3.14 --version 2>&1))."
else
    log "Installing Python 3.14..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update -qq
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 \
        apt install -y python3.14 python3.14-dev python3.14-venv
fi

# ==============================================================================
# 6. MariaDB & Redis
# ==============================================================================
if [ "$SETUP_TYPE" == "local" ]; then

    if systemctl is-active --quiet mariadb; then
        skip "MariaDB already running."
    else
        log "Installing MariaDB..."
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 \
            apt install -y mariadb-server mariadb-client
        sudo systemctl enable mariadb
        sudo systemctl start mariadb
    fi

    if [ ! -f /etc/mysql/mariadb.conf.d/99-frappe.cnf ]; then
        log "Writing MariaDB character set config..."
        cat <<EOF | sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf
[server]

[mysql]
default-character-set = utf8mb4

[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
EOF
        sudo systemctl restart mariadb
    else
        skip "MariaDB character set config already exists."
    fi

    log "Checking MariaDB root credentials..."
    if mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
        skip "MariaDB root password already set correctly."
    elif sudo mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        log "MariaDB root accessible via unix socket — setting password now..."
        sudo mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
FLUSH PRIVILEGES;
SQL
        log "MariaDB root password set."
    else
        err "Cannot access MariaDB as root. Run: sudo systemctl status mariadb"
    fi

    if systemctl is-active --quiet redis-server; then
        skip "Redis already running."
    else
        log "Installing and starting Redis..."
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 \
            apt install -y redis-server
        sudo systemctl enable redis-server
        sudo systemctl start redis-server
    fi

else
    if command -v redis-server >/dev/null 2>&1; then
        skip "redis-server binary already present."
    else
        log "Installing redis-server binary (bench init dependency)..."
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 \
            apt install -y redis-server
    fi
    sudo systemctl stop redis-server 2>/dev/null || true
    sudo systemctl disable redis-server 2>/dev/null || true

    log "Pre-flight: checking managed MariaDB at ${MARIADB_IP}..."
    mysql -h "$MARIADB_IP" -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1 \
        || err "Cannot connect to remote MariaDB at $MARIADB_IP."

    log "Pre-flight: checking managed Redis at ${REDIS_IP}..."
    redis-cli -h "$REDIS_IP" -p 6379 ping | grep -q PONG \
        || err "Cannot connect to managed Redis at $REDIS_IP."

    log "Pre-flight checks passed."
fi

# ==============================================================================
# 7. Node.js 24
# ==============================================================================
NODE_VER=$(node --version 2>/dev/null | grep -oP '(?<=v)\d+' || echo "0")
if [ "$NODE_VER" -ge 24 ] 2>/dev/null; then
    skip "Node.js $(node --version) already installed."
else
    log "Installing Node.js 24..."
    sudo apt remove -y nodejs 2>/dev/null || true
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 \
        apt install -y nodejs
fi

if command -v yarn >/dev/null 2>&1; then
    skip "yarn already installed ($(yarn --version))."
else
    log "Installing yarn..."
    sudo npm install -g yarn
fi

# ==============================================================================
# 8. wkhtmltopdf (arch-aware, idempotent)
# ==============================================================================
if command -v wkhtmltopdf >/dev/null 2>&1; then
    skip "wkhtmltopdf already installed ($(wkhtmltopdf --version 2>&1 | head -1))."
else
    WKHTML_BASE="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3"
    if [ "$SYS_ARCH" = "amd64" ]; then
        WKHTML_DEB="wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
    elif [ "$SYS_ARCH" = "arm64" ]; then
        WKHTML_DEB="wkhtmltox_0.12.6.1-3.jammy_arm64.deb"
    else
        warn "Unknown arch '$SYS_ARCH' — skipping wkhtmltopdf."
        WKHTML_DEB=""
    fi

    if [ -n "$WKHTML_DEB" ]; then
        log "Downloading wkhtmltopdf for $SYS_ARCH..."
        wget -q "${WKHTML_BASE}/${WKHTML_DEB}" -O /tmp/wkhtmltox.deb \
            || err "Failed to download wkhtmltopdf."
        sudo dpkg -i /tmp/wkhtmltox.deb || \
            sudo DEBIAN_FRONTEND=noninteractive apt install -f -y
        rm -f /tmp/wkhtmltox.deb
        log "wkhtmltopdf installed."
    fi
fi

# ==============================================================================
# 9. Frappe User
# ==============================================================================
if id -u frappe >/dev/null 2>&1; then
    skip "frappe user already exists."
else
    log "Creating frappe user..."
    sudo adduser --disabled-password --gecos "" frappe
    sudo usermod -aG sudo frappe
fi
echo "frappe ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/frappe >/dev/null
sudo chmod 0440 /etc/sudoers.d/frappe

# ==============================================================================
# 10. Bench CLI & Ansible
# ==============================================================================
if command -v bench >/dev/null 2>&1; then
    skip "bench CLI already installed ($(bench --version 2>/dev/null || echo 'unknown'))."
else
    log "Installing bench CLI and Ansible..."
    PYTHON_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)")
    PYTHON_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")
    PIP_ARGS=""
    if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 12 ]; then
        PIP_ARGS="--break-system-packages"
        log "Python 3.${PYTHON_MINOR} — using --break-system-packages."
    fi
    sudo pip3 install $PIP_ARGS --ignore-installed frappe-bench ansible \
        || err "bench CLI install failed."
    bench --version || err "bench not accessible after install."
fi

# ==============================================================================
# 11. Bench Init & ERPNext (as frappe user)
# ==============================================================================
log "Running bench/site setup as frappe user..."
log "Using site name: ${SITE_NAME}"

# NOTE: Variables are passed explicitly via 'sudo -u frappe env VAR=value'
# This is the ONLY reliable way — sudo -i resets the environment and
# single-quoted heredocs disable expansion, both of which silently lose values.

sudo -u frappe \
    env \
        SETUP_TYPE="$SETUP_TYPE" \
        SITE_NAME="$SITE_NAME" \
        DB_ROOT_PASS="$DB_ROOT_PASS" \
        ADMIN_PASS="$ADMIN_PASS" \
        MARIADB_IP="$MARIADB_IP" \
        REDIS_IP="$REDIS_IP" \
        DOMAIN_NAME="$DOMAIN_NAME" \
        INSTALL_EXTRA_APPS="$INSTALL_EXTRA_APPS" \
    bash <<'FRAPPE_EOF'

set -e

log()  { echo -e "\033[0;32m[+] $1\033[0m"; }
warn() { echo -e "\033[1;33m[!] $1\033[0m"; }
skip() { echo -e "\033[0;36m[~] SKIP: $1\033[0m"; }

# Confirm variables arrived correctly
log "Frappe shell — site: ${SITE_NAME}, db_host: ${MARIADB_IP}, setup: ${SETUP_TYPE}"

[ -z "$SITE_NAME" ]    && { echo "[x] SITE_NAME is empty — aborting."; exit 1; }
[ -z "$DB_ROOT_PASS" ] && { echo "[x] DB_ROOT_PASS is empty — aborting."; exit 1; }
[ -z "$ADMIN_PASS" ]   && { echo "[x] ADMIN_PASS is empty — aborting."; exit 1; }

# --- bench init ---
if [ -d '/home/frappe/frappe-bench' ]; then
    skip "frappe-bench already initialised."
else
    log "Running bench init with Python 3.14..."
    bench init --frappe-branch version-16 /home/frappe/frappe-bench --python python3.14
fi

cd /home/frappe/frappe-bench

# --- get ERPNext ---
if [ -d 'apps/erpnext' ]; then
    skip "ERPNext app already downloaded."
else
    log "Downloading ERPNext v16..."
    bench get-app --branch version-16 erpnext
fi

# --- managed Redis config ---
if [ "$SETUP_TYPE" = "managed" ]; then
    CURRENT_CACHE=$(jq -r '.redis_cache // ""' sites/common_site_config.json 2>/dev/null || echo "")
    if echo "$CURRENT_CACHE" | grep -q "$REDIS_IP"; then
        skip "Redis already configured in common_site_config.json."
    else
        log "Configuring Redis for managed host ${REDIS_IP}..."
        jq \
            --arg rc "redis://${REDIS_IP}:6379" \
            '.redis_cache = $rc | .redis_queue = $rc | .redis_socketio = $rc' \
            sites/common_site_config.json > sites/tmp.json \
            && mv sites/tmp.json sites/common_site_config.json
    fi
fi

# --- create site ---
if [ -d "sites/${SITE_NAME}" ]; then
    skip "Site ${SITE_NAME} already exists."
else
    log "Creating site: ${SITE_NAME} (db-host: ${MARIADB_IP})..."
    bench new-site "${SITE_NAME}" \
        --db-host "${MARIADB_IP}" \
        --db-port 3306 \
        --db-root-username root \
        --db-root-password "${DB_ROOT_PASS}" \
        --admin-password "${ADMIN_PASS}" \
        --mariadb-user-host-login-scope='%'

    log "Setting ${SITE_NAME} as default site..."
    bench use "${SITE_NAME}"

    log "Starting bench workers for install phase..."
    bench start > /tmp/bench-start.log 2>&1 &
    BENCH_PID=$!
    sleep 10

    # --- install ERPNext ---
    if bench --site "${SITE_NAME}" list-apps 2>/dev/null | grep -q "^erpnext$"; then
        skip "ERPNext already installed on site."
    else
        log "Installing ERPNext on ${SITE_NAME}..."
        bench --site "${SITE_NAME}" install-app erpnext
    fi

    # --- extra apps ---
    if [[ "$INSTALL_EXTRA_APPS" =~ ^[Yy]$ ]]; then
        declare -A EXTRA_APPS=(
            ["hrms"]="version-16|https://github.com/frappe/hrms.git"
            ["insights"]="develop|https://github.com/frappe/insights.git"
            ["india_compliance"]="version-16|https://github.com/resilient-tech/india-compliance.git"
        )
        for APP_NAME in "${!EXTRA_APPS[@]}"; do
            APP_BRANCH=$(echo "${EXTRA_APPS[$APP_NAME]}" | cut -d'|' -f1)
            APP_URL=$(echo "${EXTRA_APPS[$APP_NAME]}" | cut -d'|' -f2)

            if [ -d "apps/${APP_NAME}" ]; then
                skip "${APP_NAME} already downloaded."
            else
                log "Fetching ${APP_NAME} (branch: ${APP_BRANCH})..."
                bench get-app --branch "$APP_BRANCH" "$APP_URL" \
                    || warn "${APP_NAME} fetch failed — skipping."
            fi

            if bench --site "${SITE_NAME}" list-apps 2>/dev/null | grep -q "^${APP_NAME}$"; then
                skip "${APP_NAME} already installed on site."
            else
                bench --site "${SITE_NAME}" install-app "$APP_NAME" \
                    || warn "${APP_NAME} install failed."
            fi
        done
    fi

    log "Running migrations and clearing cache..."
    bench --site "${SITE_NAME}" migrate
    bench --site "${SITE_NAME}" clear-cache

    log "Stopping temporary bench workers..."
    kill $BENCH_PID 2>/dev/null || true
    wait $BENCH_PID 2>/dev/null || true

    if [ -n "$DOMAIN_NAME" ]; then
        log "Registering domain ${DOMAIN_NAME} for site ${SITE_NAME}..."
        bench setup add-domain "${DOMAIN_NAME}" --site "${SITE_NAME}"
    fi
fi

FRAPPE_EOF

# ==============================================================================
# 12. Production Setup (Nginx & Supervisor)
# ==============================================================================
SUPERVISOR_CONF="/home/frappe/frappe-bench/config/supervisor.conf"
NGINX_SITES_CONF="/etc/nginx/sites-available/${SITE_NAME}"
NGINX_SITES_LINK="/etc/nginx/sites-enabled/${SITE_NAME}"

# Remove default nginx config
sudo rm -f /etc/nginx/sites-enabled/default

if [ -f "$NGINX_SITES_CONF" ]; then
    skip "Production Nginx config already exists at $NGINX_SITES_CONF."
else
    log "Building frontend assets (this may take a few minutes)..."
    sudo -u frappe env HOME=/home/frappe PATH="/home/frappe/.local/bin:$PATH" \
        bash -c "cd /home/frappe/frappe-bench && bench build"

    log "Setting up production (Nginx + Supervisor)..."
    sudo -u frappe env HOME=/home/frappe PATH="/home/frappe/.local/bin:$PATH" \
        bash -c "cd /home/frappe/frappe-bench && sudo env PATH=\$PATH bench setup production frappe --yes"

    # Move bench-generated conf.d config → sites-available/sites-enabled pattern
    if [ -f /etc/nginx/conf.d/frappe-bench.conf ]; then
        log "Relocating nginx config to sites-available/${SITE_NAME}..."
        sudo mv /etc/nginx/conf.d/frappe-bench.conf "$NGINX_SITES_CONF"
    fi
fi

# Ensure symlink exists
if [ ! -L "$NGINX_SITES_LINK" ]; then
    log "Creating sites-enabled symlink..."
    sudo ln -sf "$NGINX_SITES_CONF" "$NGINX_SITES_LINK"
fi

# Supervisor symlink
if [ ! -L /etc/supervisor/conf.d/frappe-bench.conf ]; then
    log "Creating Supervisor symlink..."
    sudo ln -sf "$SUPERVISOR_CONF" /etc/supervisor/conf.d/frappe-bench.conf
fi
sudo systemctl restart supervisor || true
sleep 3
sudo supervisorctl reread && sudo supervisorctl update

# Nginx permissions
log "Ensuring Nginx file permissions..."
sudo chmod o+x /home/frappe
sudo chmod o+x /home/frappe/frappe-bench
sudo chmod -R o+r /home/frappe/frappe-bench/sites/assets

# ==============================================================================
# 13. Managed: remove local Redis from Supervisor
# ==============================================================================
if [ "$SETUP_TYPE" == "managed" ]; then
    if grep -q "^# \[group:frappe-bench-redis\]" "$SUPERVISOR_CONF" 2>/dev/null; then
        skip "Local Redis already removed from Supervisor config."
    else
        log "Removing local Redis from Supervisor config..."
        sudo sed -i '/^\[group:frappe-bench-redis\]/,/^$/s/^/# /' "$SUPERVISOR_CONF"
        sudo sed -i '/^\[program:frappe-bench-redis-cache\]/,/^$/s/^/# /' "$SUPERVISOR_CONF"
        sudo sed -i '/^\[program:frappe-bench-redis-queue\]/,/^$/s/^/# /' "$SUPERVISOR_CONF"
        sudo supervisorctl reread && sudo supervisorctl update
    fi
fi

# ==============================================================================
# 14. Nginx server_name Fix
# Always runs — sets server_name to:
#   - the domain entered at setup (if provided), OR
#   - the public IP of the server (so http://<ip> works without a domain)
# ==============================================================================
if [ -f "$NGINX_SITES_CONF" ]; then
    if grep -q "server_name.*${SERVER_IDENTITY}" "$NGINX_SITES_CONF"; then
        skip "Nginx server_name already set to ${SERVER_IDENTITY}."
    else
        log "Setting server_name to ${SERVER_IDENTITY} in Nginx config..."
        # Replaces ANY value bench put in server_name (site name, localhost, etc.)
        sudo sed -i "s/^\(\s*server_name\s\+\).\+;/\1${SERVER_IDENTITY};/" \
            "$NGINX_SITES_CONF"

        # Verify
        if grep -q "server_name.*${SERVER_IDENTITY}" "$NGINX_SITES_CONF"; then
            log "server_name set to ${SERVER_IDENTITY} successfully."
        else
            warn "sed replacement may have failed. Current server_name lines:"
            grep "server_name" "$NGINX_SITES_CONF" || true
        fi
    fi
else
    warn "Nginx config not found at $NGINX_SITES_CONF — skipping server_name update."
fi

sudo nginx -t && sudo systemctl reload nginx \
    || warn "Nginx reload failed. Check: sudo nginx -t"

# ==============================================================================
# 15. SSL
# ==============================================================================
if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    if sudo certbot certificates 2>/dev/null | grep -q "$DOMAIN_NAME"; then
        skip "SSL certificate for $DOMAIN_NAME already exists."
    else
        log "Setting up Let's Encrypt SSL for $DOMAIN_NAME..."
        sudo snap install --classic certbot 2>/dev/null \
            || sudo DEBIAN_FRONTEND=noninteractive apt install -y certbot python3-certbot-nginx
        sudo ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
        sudo certbot --nginx -d "$DOMAIN_NAME" \
            --non-interactive --agree-tos -m "$SSL_EMAIL" \
            || warn "SSL setup failed. Run manually: sudo certbot --nginx -d $DOMAIN_NAME"
    fi
fi

# ==============================================================================
# Done
# ==============================================================================
log "================================================================="
log "       ERPNext v16 Installation Complete!"
log "================================================================="
log "Site Name:      $SITE_NAME"
log "Admin URL:      http${ENABLE_SSL:+s}://${SERVER_IDENTITY}"
log "Username:       Administrator"
log "Password:       (as entered during setup)"
log "Nginx config:   /etc/nginx/sites-enabled/${SITE_NAME}"
[ "$SETUP_TYPE" == "managed" ] && log "MariaDB:        $MARIADB_IP"
[ "$SETUP_TYPE" == "managed" ] && log "Redis:          $REDIS_IP"
echo "================================================================="