#!/usr/bin/env bash
# ============================================================================
# erp_monolithic_setup.sh
# Monolithic ERPNext setup — prompts for all config interactively,
# then runs the full unattended install.
# Tested on: Ubuntu 22.04 LTS
# Usage: sudo bash erp_monolithic_setup.sh
# ============================================================================
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✓]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
step()    { echo -e "\n${BOLD}${GREEN}━━━ $* ━━━${NC}"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
label()   { echo -e "${BOLD}$*${NC}"; }

# ─── Must run as root ────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script with sudo: sudo bash $0"

# ─── Prompt helpers ──────────────────────────────────────────────────────────
# prompt_required <var_name> <display_label> <hint>
prompt_required() {
  local var_name="$1" display="$2" hint="$3" value=""
  while [[ -z "$value" ]]; do
    echo -ne "${BOLD}${display}${NC} ${DIM}${hint}${NC}: "
    read -r value
    [[ -z "$value" ]] && echo -e "${RED}  ✗ This field is required.${NC}"
  done
  export "$var_name"="$value"
}

# prompt_password <var_name> <display_label> <hint>
prompt_password() {
  local var_name="$1" display="$2" hint="$3" value="" confirm=""
  while true; do
    echo -ne "${BOLD}${display}${NC} ${DIM}${hint}${NC}: "
    read -rsp "" value; echo
    [[ -z "$value" ]] && { echo -e "${RED}  ✗ Password cannot be empty.${NC}"; continue; }
    echo -ne "${BOLD}  Confirm password${NC}: "
    read -rsp "" confirm; echo
    [[ "$value" == "$confirm" ]] && break
    echo -e "${RED}  ✗ Passwords do not match. Try again.${NC}"
  done
  export "$var_name"="$value"
}

# prompt_optional <var_name> <display_label> <hint> <default>
prompt_optional() {
  local var_name="$1" display="$2" hint="$3" default="$4" value=""
  echo -ne "${BOLD}${display}${NC} ${DIM}${hint}${NC}"
  [[ -n "$default" ]] && echo -ne " ${DIM}[default: ${default}]${NC}"
  echo -n ": "
  read -r value
  export "$var_name"="${value:-$default}"
}

# prompt_yn <var_name> <display_label> <default y|n>
prompt_yn() {
  local var_name="$1" display="$2" default="${3:-n}" answer=""
  local choices; [[ "$default" == "y" ]] && choices="Y/n" || choices="y/N"
  echo -ne "${BOLD}${display}${NC} ${DIM}[${choices}]${NC}: "
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]] && export "$var_name"=true || export "$var_name"=false
}

# ════════════════════════════════════════════════════════════════════════════════
# INTERACTIVE CONFIGURATION PROMPTS
# ════════════════════════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${GREEN}"
echo "  ███████╗██████╗ ██████╗ ███╗   ██╗███████╗██╗  ██╗████████╗"
echo "  ██╔════╝██╔══██╗██╔══██╗████╗  ██║██╔════╝╚██╗██╔╝╚══██╔══╝"
echo "  █████╗  ██████╔╝██████╔╝██╔██╗ ██║█████╗   ╚███╔╝    ██║   "
echo "  ██╔══╝  ██╔══██╗██╔═══╝ ██║╚██╗██║██╔══╝   ██╔██╗    ██║   "
echo "  ███████╗██║  ██║██║     ██║ ╚████║███████╗██╔╝ ██╗   ██║   "
echo "  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝   "
echo -e "${NC}"
echo -e "  ${BOLD}Monolithic Setup — ERPNext + MariaDB + Redis on one server${NC}"
echo -e "  ${DIM}Ubuntu 22.04 LTS${NC}"
echo ""
echo -e "  Answer the questions below. Passwords are hidden while typing."
echo -e "  Press ${BOLD}Ctrl+C${NC} at any time to abort."
echo ""
echo "────────────────────────────────────────────────────────────"
echo ""

# ─── Section 1: Site ─────────────────────────────────────────────────────────
label "[ 1 / 5 ]  Site Configuration"
echo ""

prompt_required SITE_NAME \
  "  Site name" \
  "(e.g. mycompany.local  or  mycompany)"

echo ""
echo -e "  ${DIM}Which ERPNext version do you want to install?${NC}"
echo -e "  ${DIM}  1) version-15  (stable, recommended)${NC}"
echo -e "  ${DIM}  2) version-16  (latest)${NC}"
echo -e "  ${DIM}  3) version-14  (LTS)${NC}"
echo -ne "${BOLD}  Branch${NC} ${DIM}[default: version-15]${NC}: "
read -r _branch_input
case "$_branch_input" in
  1|"")  FRAPPE_BRANCH="version-15" ;;
  2)     FRAPPE_BRANCH="version-16" ;;
  3)     FRAPPE_BRANCH="version-14" ;;
  version-1[456]) FRAPPE_BRANCH="$_branch_input" ;;
  *)     warn "Unrecognised input — defaulting to version-15"; FRAPPE_BRANCH="version-15" ;;
esac
export FRAPPE_BRANCH
echo ""

# ─── Section 2: Database ─────────────────────────────────────────────────────
echo "────────────────────────────────────────────────────────────"
label "[ 2 / 5 ]  MariaDB Root Password"
echo -e "  ${DIM}This password will be set on the MariaDB root account.${NC}"
echo -e "  ${DIM}bench uses this to create the site database.${NC}"
echo ""

prompt_password DB_ROOT_PASS \
  "  MariaDB root password" \
  "(min 8 chars recommended)"
echo ""

# ─── Section 3: ERPNext admin ────────────────────────────────────────────────
echo "────────────────────────────────────────────────────────────"
label "[ 3 / 5 ]  ERPNext Administrator Password"
echo -e "  ${DIM}This is the login password for the 'Administrator' account in ERPNext.${NC}"
echo ""

prompt_password ADMIN_PASS \
  "  ERPNext admin password" \
  "(for ERPNext login)"

echo ""
echo -ne "${BOLD}  Linux 'frappe' user password${NC} ${DIM}[press Enter to use same as admin]${NC}: "
read -rsp "" _frappe_pass_input; echo
export FRAPPE_USER_PASS="${_frappe_pass_input:-$ADMIN_PASS}"
echo ""

# ─── Section 4: Domain + SSL ─────────────────────────────────────────────────
echo "────────────────────────────────────────────────────────────"
label "[ 4 / 5 ]  Domain & SSL"
echo -e "  ${DIM}Leave blank to access via IP address only.${NC}"
echo ""

prompt_optional DOMAIN \
  "  Public domain" \
  "(e.g. erp.mycompany.com — leave blank for IP-only)" \
  ""

SKIP_SSL=false
if [[ -n "$DOMAIN" ]]; then
  echo ""
  prompt_yn SKIP_SSL \
    "  Skip SSL for now? (use if DNS is not yet pointed to this server)" \
    "n"
fi
export SKIP_SSL
echo ""

# ─── Section 5: Optional modules ─────────────────────────────────────────────
echo "────────────────────────────────────────────────────────────"
label "[ 5 / 5 ]  Optional Modules"
echo ""

prompt_yn INSTALL_HRMS \
  "  Install HRMS (HR & Payroll module)?" \
  "n"
export INSTALL_HRMS
echo ""

# ─── Pre-flight: OS check ────────────────────────────────────────────────────
OS_ID=$(. /etc/os-release && echo "$ID")
OS_VER=$(. /etc/os-release && echo "$VERSION_ID")
if [[ "$OS_ID" != "ubuntu" || "$OS_VER" != "22.04" ]]; then
  warn "This script is tested on Ubuntu 22.04. Detected: ${OS_ID} ${OS_VER}"
  echo -ne "${BOLD}  Continue anyway?${NC} ${DIM}[y/N]${NC}: "
  read -r _os_confirm
  [[ "$_os_confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
fi

# ─── Summary & final confirmation ────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Configuration Summary${NC}"
echo "────────────────────────────────────────────────────────────"
echo -e "  Site name      : ${GREEN}${SITE_NAME}${NC}"
echo -e "  Branch         : ${GREEN}${FRAPPE_BRANCH}${NC}"
echo -e "  Domain         : ${GREEN}${DOMAIN:-'(none — IP access only)'}${NC}"
echo -e "  SSL            : ${GREEN}$([ "$SKIP_SSL" = true ] && echo 'Skipped' || echo 'Yes (certbot)')${NC}"
echo -e "  HRMS           : ${GREEN}${INSTALL_HRMS}${NC}"
echo -e "  Bench dir      : ${GREEN}/home/frappe/frappe-bench${NC}"
echo -e "  MariaDB pass   : ${GREEN}(set)${NC}"
echo -e "  Admin pass     : ${GREEN}(set)${NC}"
echo ""
echo -e "  ${YELLOW}The server will now be configured. This takes 15–30 minutes.${NC}"
echo -e "  ${YELLOW}Do not close this terminal.${NC}"
echo ""
echo -ne "${BOLD}  Start installation?${NC} ${DIM}[y/N]${NC}: "
read -r _final_confirm
[[ "$_final_confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

# ─── Internal constants ───────────────────────────────────────────────────────
FRAPPE_USER="frappe"
BENCH_DIR="/home/frappe/frappe-bench"

# ─── Helpers: run commands as frappe user ────────────────────────────────────
as_frappe() {
  sudo -u "$FRAPPE_USER" bash -l -c "$1"
}

as_frappe_bench() {
  sudo -u "$FRAPPE_USER" bash -l -c "cd ${BENCH_DIR} && $1"
}

# ─── Tee all output to log ───────────────────────────────────────────────────
LOG_FILE="/var/log/erp_setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
info "Full install log: ${LOG_FILE}"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 1 — System packages
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 1 — System packages"

apt update -qq && DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq

DEBIAN_FRONTEND=noninteractive apt install -y -qq \
  git curl wget \
  python3 python3-dev python3-pip python3-venv \
  build-essential \
  libffi-dev libssl-dev \
  software-properties-common \
  xvfb libfontconfig \
  cron vim

success "Base packages installed"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 2 — MariaDB
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 2 — MariaDB"

DEBIAN_FRONTEND=noninteractive apt install -y -qq mariadb-server mariadb-client
systemctl start mariadb
systemctl enable mariadb

# CRITICAL: section order [server] → [mysql] → [mysqld] must be preserved.
# Wrong order causes bench new-site to fail with collation mismatches.
cat > /etc/mysql/mariadb.conf.d/60-frappe.cnf << 'MARIADB_CONF'
[server]

[mysql]
default-character-set = utf8mb4

[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
MARIADB_CONF

systemctl restart mariadb
success "MariaDB utf8mb4 charset configured"

# CRITICAL: switch root from unix_socket auth to password auth.
# pymysql (used by bench) cannot use unix_socket — gets error 1698 otherwise.
mysql -u root << MYSQL_SETUP
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SETUP

success "MariaDB secured — root password set, unix_socket auth disabled"

CHARSET=$(mysql -u root -p"${DB_ROOT_PASS}" -se "SHOW VARIABLES LIKE 'character_set_server';" 2>/dev/null | awk '{print $2}')
[[ "$CHARSET" == "utf8mb4" ]] \
  && success "Verified: character_set_server = utf8mb4" \
  || error "character_set_server = '${CHARSET}', expected utf8mb4. Check /etc/mysql/mariadb.conf.d/60-frappe.cnf"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 3 — Redis
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 3 — Redis"

DEBIAN_FRONTEND=noninteractive apt install -y -qq redis-server
systemctl start redis-server
systemctl enable redis-server

REDIS_PING=$(redis-cli ping 2>/dev/null || echo "FAILED")
[[ "$REDIS_PING" == "PONG" ]] \
  && success "Redis running — PONG received" \
  || error "Redis not responding. Check: sudo systemctl status redis-server"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Node.js 20 + yarn
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 4 — Node.js 20 + yarn"

# Node 20 required — Node 18 breaks HRMS and India Compliance builds.
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt install -y -qq nodejs

NODE_VER=$(node -v)
[[ "$NODE_VER" == v20* ]] \
  && success "Node.js ${NODE_VER} installed" \
  || warn "Expected Node v20.x, got ${NODE_VER} — build failures may occur"

npm install -g yarn --quiet
success "yarn $(yarn -v) installed"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 5 — wkhtmltopdf (patched QT build)
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 5 — wkhtmltopdf"

# apt version lacks patched QT — PDF generation silently fails without it.
if command -v wkhtmltopdf &>/dev/null && wkhtmltopdf --version 2>&1 | grep -q "patched qt"; then
  success "wkhtmltopdf already installed with patched qt"
else
  WKHTMLTOPDF_DEB="/tmp/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
  wget -q -O "$WKHTMLTOPDF_DEB" \
    "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
  dpkg -i "$WKHTMLTOPDF_DEB" 2>/dev/null || DEBIAN_FRONTEND=noninteractive apt install -f -y -qq
  rm -f "$WKHTMLTOPDF_DEB"
  wkhtmltopdf --version 2>&1 | grep -q "patched qt" \
    && success "wkhtmltopdf installed: $(wkhtmltopdf --version 2>&1 | head -1)" \
    || warn "wkhtmltopdf installed without patched qt — PDF generation may fail"
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 6 — frappe system user
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 6 — System user: ${FRAPPE_USER}"

if id "$FRAPPE_USER" &>/dev/null; then
  success "User '${FRAPPE_USER}' already exists"
else
  adduser --disabled-password --gecos "" "$FRAPPE_USER"
  success "User '${FRAPPE_USER}' created"
fi

echo "${FRAPPE_USER}:${FRAPPE_USER_PASS}" | chpasswd
usermod -aG sudo "$FRAPPE_USER"
success "User '${FRAPPE_USER}' password set and added to sudo group"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 7 — bench CLI
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 7 — bench CLI"

pip3 install -q frappe-bench

FRAPPE_BASHRC="/home/${FRAPPE_USER}/.bashrc"
grep -q "/.local/bin" "$FRAPPE_BASHRC" 2>/dev/null \
  || echo 'export PATH=$PATH:$HOME/.local/bin:/usr/local/bin' >> "$FRAPPE_BASHRC"

success "bench $(bench --version 2>/dev/null || echo 'installed') ready"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 8 — bench init
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 8 — bench init (Frappe ${FRAPPE_BRANCH})"

if [[ -d "$BENCH_DIR" ]]; then
  warn "Bench directory already exists — skipping init (delete ${BENCH_DIR} to start fresh)"
else
  info "Cloning Frappe framework + setting up virtualenv (2–5 min)..."
  as_frappe "bench init --frappe-branch ${FRAPPE_BRANCH} ${BENCH_DIR}"
  success "Bench initialised at ${BENCH_DIR}"
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 9 — Download apps
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 9 — Download ERPNext app"

if [[ -d "${BENCH_DIR}/apps/erpnext" ]]; then
  success "ERPNext app already present — skipping download"
else
  info "Cloning ERPNext ${FRAPPE_BRANCH} from GitHub (2–5 min)..."
  as_frappe_bench "bench get-app --branch ${FRAPPE_BRANCH} erpnext"
  success "ERPNext downloaded"
fi

if [[ "$INSTALL_HRMS" == true ]]; then
  if [[ -d "${BENCH_DIR}/apps/hrms" ]]; then
    success "HRMS already present — skipping"
  else
    info "Downloading HRMS..."
    as_frappe_bench "bench get-app hrms"
    success "HRMS downloaded"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 10 — Create site
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 10 — Create site: ${SITE_NAME}"

if [[ -d "${BENCH_DIR}/sites/${SITE_NAME}" ]]; then
  success "Site '${SITE_NAME}' already exists — skipping creation"
else
  info "Creating site (initialises MariaDB database + site_config.json)..."
  # Passwords passed via env vars — safe for special characters in passwords
  sudo -u "$FRAPPE_USER" \
    ERP_DB_PASS="${DB_ROOT_PASS}" ERP_ADMIN_PASS="${ADMIN_PASS}" ERP_SITE="${SITE_NAME}" \
    bash -l -c "cd ${BENCH_DIR} && bench new-site \"\$ERP_SITE\" \
      --mariadb-root-password \"\$ERP_DB_PASS\" \
      --admin-password \"\$ERP_ADMIN_PASS\""
  success "Site '${SITE_NAME}' created"
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 11 — Install apps on site
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 11 — Install ERPNext on site (5–15 min)"

info "Running database migrations for all ERPNext doctypes..."
as_frappe_bench "bench --site ${SITE_NAME} install-app erpnext"
success "ERPNext installed on '${SITE_NAME}'"

if [[ "$INSTALL_HRMS" == true ]]; then
  info "Installing HRMS..."
  as_frappe_bench "bench --site ${SITE_NAME} install-app hrms"
  success "HRMS installed"
fi

as_frappe_bench "bench use ${SITE_NAME}"
success "Default site → '${SITE_NAME}'"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 12 — Production setup (Nginx + Supervisor)
# ════════════════════════════════════════════════════════════════════════════════
step "PHASE 12 — Production setup"

info "Generating Nginx + Supervisor configs via bench..."
env PATH="$PATH:/usr/local/bin" bench setup production "$FRAPPE_USER" --yes

# CRITICAL: bench setup production writes supervisor config to bench-local
# config/ but does NOT always symlink to /etc/supervisor/conf.d/ automatically.
# Without this, supervisord starts empty — no web, no workers, no scheduler.
info "Ensuring supervisor config symlink exists..."
ln -sf "${BENCH_DIR}/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf
supervisorctl reread
supervisorctl update
success "Supervisor config linked and reloaded"

# CRITICAL: Nginx runs as www-data. /home/frappe defaults to mode 750 which
# blocks www-data from traversing to sites/assets/ → 403 on all static files.
info "Fixing Nginx static asset permissions..."
chmod o+x /home/${FRAPPE_USER}
chmod o+x ${BENCH_DIR}
chmod -R o+r ${BENCH_DIR}/sites/assets
success "Static asset permissions fixed"

# Remove default Nginx site — it would intercept all requests before frappe config
[[ -f /etc/nginx/sites-enabled/default ]] && rm /etc/nginx/sites-enabled/default \
  && info "Removed default Nginx site"

nginx -t && systemctl reload nginx
systemctl enable supervisor nginx
success "Nginx reloaded and supervisor enabled on boot"

info "Waiting for processes to start..."
sleep 5
info "Supervisor process status:"
supervisorctl status || true

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 13 — Domain mapping (if provided)
# ════════════════════════════════════════════════════════════════════════════════
if [[ -n "$DOMAIN" ]]; then
  step "PHASE 13 — Domain: ${DOMAIN}"

  as_frappe_bench "bench setup add-domain ${DOMAIN} --site ${SITE_NAME}"
  nginx -t && systemctl reload nginx
  success "Domain '${DOMAIN}' → site '${SITE_NAME}'"

  sudo -u "$FRAPPE_USER" bash -l -c \
    "cd ${BENCH_DIR} && bench --site ${SITE_NAME} set-config host_name 'https://${DOMAIN}'" 2>/dev/null || true

  # ─── SSL ─────────────────────────────────────────────────────────────────────
  if [[ "$SKIP_SSL" == false ]]; then
    step "PHASE 14 — SSL (Let's Encrypt)"

    snap install --classic certbot 2>/dev/null || true
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true

    SERVER_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
    info "Server public IP: ${SERVER_IP}"
    info "Ensure DNS A record: ${DOMAIN} → ${SERVER_IP}"

    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}"; then
      nginx -t && systemctl reload nginx
      success "SSL certificate issued for ${DOMAIN}"
    else
      warn "certbot failed — DNS may not be pointed yet."
      warn "Run manually when ready: sudo certbot --nginx -d ${DOMAIN}"
    fi
  else
    warn "SSL skipped. Run when DNS is ready: sudo certbot --nginx -d ${DOMAIN}"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# DONE
# ════════════════════════════════════════════════════════════════════════════════
SERVER_IP=$(hostname -I | awk '{print $1}')

if [[ -n "$DOMAIN" && "$SKIP_SSL" == false ]]; then
  ACCESS_URL="https://${DOMAIN}"
elif [[ -n "$DOMAIN" ]]; then
  ACCESS_URL="http://${DOMAIN}"
else
  ACCESS_URL="http://${SERVER_IP}"
fi

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ERPNext Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}URL         :${NC} ${ACCESS_URL}"
echo -e "  ${BOLD}Login       :${NC} Administrator"
echo -e "  ${BOLD}Password    :${NC} (value you entered for ERPNext admin)"
echo -e "  ${BOLD}Site name   :${NC} ${SITE_NAME}"
echo -e "  ${BOLD}Bench dir   :${NC} ${BENCH_DIR}"
echo -e "  ${BOLD}Install log :${NC} ${LOG_FILE}"
echo ""
echo "  Useful commands:"
echo "  → Process status  : sudo supervisorctl status"
echo "  → Live logs       : tail -f ${BENCH_DIR}/logs/*.log"
echo "  → Backup          : cd ${BENCH_DIR} && bench --site ${SITE_NAME} backup"
echo "  → Update          : cd ${BENCH_DIR} && bench update"
echo ""
echo -e "  ${YELLOW}If any supervisor process shows FATAL/STOPPED:${NC}"
echo "    sudo supervisorctl reread && sudo supervisorctl update"
echo "    tail -f ${BENCH_DIR}/logs/web.error.log"
echo ""
