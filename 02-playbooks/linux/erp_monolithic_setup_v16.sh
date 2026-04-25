#!/usr/bin/env bash
# ============================================================================
# erp_monolithic_setup_v16.sh
# Monolithic ERPNext v16 setup — prompts for all config interactively,
# then runs the full unattended install.
# Tested on: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
#
# v16 vs v15 differences handled in this script:
#   - Python 3.14 required (via deadsnakes PPA) — not 3.10
#   - Node.js 24 required — not 20 (v16 package.json enforces >=24)
#   - New packages: pkg-config, libmariadb-dev, libmariadb-dev-compat
#   - PEP 668: pip installs need --break-system-packages (Python 3.12 ships in Ubuntu 22.04)
#   - ansible must be pre-installed before bench setup production
#   - bench init must pass --python python3.14
#   - bench new-site flag changed: --db-root-password + --mariadb-user-host-login-scope='%'
#   - install-app requires Redis to be running (bench start & before install)
#   - bench build must run before Nginx serves assets
#   - frappe user gets NOPASSWD sudoers entry (bench setup production needs it)
#
# Usage: sudo bash erp_monolithic_setup_v16.sh
# ============================================================================
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── Error trap ───────────────────────────────────────────────────────────────
# LOG_FILE is set later (after prompts), but the variable is referenced here.
# Declaring it empty now so the trap message degrades gracefully if it fires early.
LOG_FILE=""
CURRENT_PHASE="Initializing"
trap '
  echo -e "\n${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${RED}  FAILED in: ${CURRENT_PHASE}  (line ${LINENO})${NC}" >&2
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${YELLOW}  The command above exited with a non-zero status.${NC}" >&2
  if [[ -n "${LOG_FILE}" ]]; then
    echo -e "${YELLOW}  Full log: ${LOG_FILE}${NC}" >&2
    echo -e "${YELLOW}  Last 20 log lines:${NC}" >&2
    tail -20 "${LOG_FILE}" >&2 2>/dev/null || true
  fi
  echo -e "${YELLOW}  Fix the issue above, then re-run the script — completed phases are skipped.${NC}" >&2
' ERR

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✓]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
step()    { echo -e "\n${BOLD}${GREEN}━━━ $* ━━━${NC}"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
label()   { echo -e "${BOLD}$*${NC}"; }

# ─── Must run as root ────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script with sudo: sudo bash $0"

# ─── Prompt helpers ──────────────────────────────────────────────────────────
prompt_required() {
  local var_name="$1" display="$2" hint="$3" value=""
  while [[ -z "$value" ]]; do
    echo -ne "${BOLD}${display}${NC} ${DIM}${hint}${NC}: "
    read -r value
    [[ -z "$value" ]] && echo -e "${RED}  ✗ This field is required.${NC}"
  done
  export "$var_name"="$value"
}

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

prompt_optional() {
  local var_name="$1" display="$2" hint="$3" default="$4" value=""
  echo -ne "${BOLD}${display}${NC} ${DIM}${hint}${NC}"
  [[ -n "$default" ]] && echo -ne " ${DIM}[default: ${default}]${NC}"
  echo -n ": "
  read -r value
  export "$var_name"="${value:-$default}"
}

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
echo -e "  ${BOLD}Monolithic Setup — ERPNext v16 + MariaDB + Redis on one server${NC}"
echo -e "  ${DIM}Ubuntu 22.04 LTS / 24.04 LTS  │  Python 3.14  │  Node.js 24${NC}"
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
echo -e "  ${DIM}ERPNext version branch:${NC}"
echo -e "  ${DIM}  1) version-16  (latest — this script is optimised for v16)${NC}"
echo -e "  ${DIM}  2) version-15  (use erp_monolithic_setup_v15.sh instead)${NC}"
echo -ne "${BOLD}  Branch${NC} ${DIM}[default: version-16]${NC}: "
read -r _branch_input
case "$_branch_input" in
  2|version-15) warn "Use erp_monolithic_setup_v15.sh for version-15."; exit 1 ;;
  1|""|version-16) FRAPPE_BRANCH="version-16" ;;
  version-1[456]) FRAPPE_BRANCH="$_branch_input" ;;
  *) warn "Unrecognised input — defaulting to version-16"; FRAPPE_BRANCH="version-16" ;;
esac
export FRAPPE_BRANCH
echo ""

# ─── Section 2: Database ─────────────────────────────────────────────────────
echo "────────────────────────────────────────────────────────────"
label "[ 2 / 5 ]  MariaDB Root Password"
echo -e "  ${DIM}Set on the MariaDB root account. bench uses this to create the site DB.${NC}"
echo ""

prompt_password DB_ROOT_PASS \
  "  MariaDB root password" \
  "(min 8 chars recommended)"
echo ""

# ─── Section 3: ERPNext admin ────────────────────────────────────────────────
echo "────────────────────────────────────────────────────────────"
label "[ 3 / 5 ]  ERPNext Administrator Password"
echo -e "  ${DIM}Login password for the 'Administrator' account in ERPNext.${NC}"
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
  "(e.g. erp.mycompany.com — blank for IP-only)" \
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
OS_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-}")
export OS_VER OS_CODENAME

if [[ "$OS_ID" != "ubuntu" || ( "$OS_VER" != "22.04" && "$OS_VER" != "24.04" ) ]]; then
  warn "This script is tested on Ubuntu 22.04 and 24.04. Detected: ${OS_ID} ${OS_VER}"
  echo -ne "${BOLD}  Continue anyway?${NC} ${DIM}[y/N]${NC}: "
  read -r _os_confirm
  [[ "$_os_confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
else
  success "OS check passed: Ubuntu ${OS_VER} (${OS_CODENAME})"
fi

# ─── Summary & confirmation ───────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Configuration Summary${NC}"
echo "────────────────────────────────────────────────────────────"
echo -e "  ERPNext version : ${GREEN}${FRAPPE_BRANCH}${NC}"
echo -e "  Site name       : ${GREEN}${SITE_NAME}${NC}"
echo -e "  Python          : ${GREEN}3.14 (via deadsnakes PPA)${NC}"
echo -e "  Node.js         : ${GREEN}24${NC}"
echo -e "  Domain          : ${GREEN}${DOMAIN:-'(none — IP access only)'}${NC}"
echo -e "  SSL             : ${GREEN}$([ "$SKIP_SSL" = true ] && echo 'Skipped' || echo 'Yes (certbot)')${NC}"
echo -e "  HRMS            : ${GREEN}${INSTALL_HRMS}${NC}"
echo -e "  OS              : ${GREEN}Ubuntu ${OS_VER} (${OS_CODENAME})${NC}"
echo -e "  Bench dir       : ${GREEN}/home/frappe/frappe-bench${NC}"
echo -e "  MariaDB pass    : ${GREEN}(set)${NC}"
echo -e "  Admin pass      : ${GREEN}(set)${NC}"
echo ""
echo -e "  ${YELLOW}Installation takes 20–40 minutes. Do not close this terminal.${NC}"
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
LOG_FILE="/var/log/erp_setup_v16_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
info "Full install log: ${LOG_FILE}"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 1 — System packages
# v16 additions: pkg-config, libmariadb-dev, libmariadb-dev-compat
# Without pkg-config + libmariadb-dev, bench init fails compiling mysqlclient.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 1 — System packages"
step "PHASE 1 — System packages (v16 additions: pkg-config, libmariadb-dev)"

# Suppress interactive service restart prompts during apt upgrade
echo '* libraries/restart-without-asking boolean true' | debconf-set-selections

apt update -qq && DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq

DEBIAN_FRONTEND=noninteractive apt install -y -qq \
  git curl wget \
  python3 python3-dev python3-pip python3-venv \
  build-essential \
  libffi-dev libssl-dev \
  software-properties-common \
  xvfb libfontconfig \
  cron vim \
  nginx supervisor \
  pkg-config \
  libmariadb-dev \
  libmariadb-dev-compat

# Verify pkg-config can find MariaDB headers — bench init needs this
if pkg-config --exists mariadb 2>/dev/null; then
  success "pkg-config found MariaDB headers"
else
  warn "pkg-config could not find MariaDB headers — bench init may fail at mysqlclient"
fi

success "Base packages installed"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Python 3.14 (NEW in v16)
# Ubuntu 22.04 ships Python 3.10. v16 requires exactly Python 3.14 —
# the 'type' alias syntax (type X = ...) was added in 3.12 but Frappe v16.13+
# pins to Python>=3.14,<3.15. 3.12 and 3.13 are not sufficient.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 2 — Python 3.14"
step "PHASE 2 — Python 3.14 (required for v16)"

info "Adding deadsnakes PPA..."
add-apt-repository ppa:deadsnakes/ppa -y >/dev/null 2>&1
apt update -qq

info "Installing Python 3.14..."
DEBIAN_FRONTEND=noninteractive apt install -y -qq python3.14 python3.14-dev python3.14-venv

PY_VER=$(python3.14 --version 2>&1)
[[ "$PY_VER" == Python\ 3.14* ]] \
  && success "Python 3.14 installed: ${PY_VER}" \
  || error "Python 3.14 installation failed. Got: ${PY_VER}"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 3 — MariaDB
# Section order [server] → [mysql] → [mysqld] is critical — wrong order
# causes collation mismatches at bench new-site.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 3 — MariaDB"
step "PHASE 3 — MariaDB"

DEBIAN_FRONTEND=noninteractive apt install -y -qq mariadb-server mariadb-client
systemctl start mariadb
systemctl enable mariadb

# Using 99-frappe.cnf (higher priority than 50-server.cnf, avoids conflicts)
info "Writing MariaDB utf8mb4 config (/etc/mysql/mariadb.conf.d/99-frappe.cnf)..."
cat > /etc/mysql/mariadb.conf.d/99-frappe.cnf << 'MARIADB_CONF'
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

# CRITICAL: switch root from unix_socket to password auth.
# pymysql (bench's DB driver) cannot use unix_socket — fails with error 1698.
info "Securing MariaDB and switching root to password auth..."
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
  || error "character_set_server = '${CHARSET}', expected utf8mb4. Check /etc/mysql/mariadb.conf.d/99-frappe.cnf"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Redis
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 4 — Redis"
step "PHASE 4 — Redis"

DEBIAN_FRONTEND=noninteractive apt install -y -qq redis-server
systemctl start redis-server
systemctl enable redis-server

REDIS_PING=$(redis-cli ping 2>/dev/null || echo "FAILED")
[[ "$REDIS_PING" == "PONG" ]] \
  && success "Redis running — PONG received" \
  || error "Redis not responding. Check: sudo systemctl status redis-server"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 5 — Node.js 24 + yarn (v16 requires Node 24, NOT 20)
# Frappe v16 package.json enforces engine: "node >= 24".
# Using Node 20 produces: "The engine node is incompatible with this module."
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 5 — Node.js 24 + yarn"
step "PHASE 5 — Node.js 24 + yarn (v16 requires 24, not 20)"

# Remove existing Node if present (could be wrong version)
if command -v node &>/dev/null; then
  EXISTING_NODE=$(node -v)
  if [[ "$EXISTING_NODE" != v24* ]]; then
    info "Removing existing Node.js ${EXISTING_NODE}..."
    DEBIAN_FRONTEND=noninteractive apt remove -y -qq nodejs 2>/dev/null || true
    apt autoremove -y -qq 2>/dev/null || true
  fi
fi

info "Installing Node.js 24 via NodeSource..."
# Output NOT suppressed — NodeSource errors must be visible for set -euo pipefail to catch them
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
DEBIAN_FRONTEND=noninteractive apt install -y nodejs

NODE_VER=$(node -v)
[[ "$NODE_VER" == v24* ]] \
  && success "Node.js ${NODE_VER} installed" \
  || error "Expected Node v24.x, got ${NODE_VER}. Frappe v16 will fail with this version."

npm install -g yarn --quiet
success "yarn $(yarn -v) installed"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 6 — wkhtmltopdf (patched QT build — same as v15)
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 6 — wkhtmltopdf"
step "PHASE 6 — wkhtmltopdf (patched QT build)"

if command -v wkhtmltopdf &>/dev/null && wkhtmltopdf --version 2>&1 | grep -q "patched qt"; then
  success "wkhtmltopdf already installed with patched qt"
else
  WKHTMLTOPDF_DEB="/tmp/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
  wget -q -O "$WKHTMLTOPDF_DEB" \
    "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"

  # On Ubuntu 24.04 (noble), the jammy .deb may have unresolvable dependency versions.
  # dpkg --force-depends installs it anyway; apt -f install cleans up what it can.
  if [[ "$OS_VER" == "24.04" ]]; then
    dpkg --force-depends -i "$WKHTMLTOPDF_DEB" 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt install -f -y -qq 2>/dev/null || true
  else
    dpkg -i "$WKHTMLTOPDF_DEB" 2>/dev/null || DEBIAN_FRONTEND=noninteractive apt install -f -y -qq
  fi

  rm -f "$WKHTMLTOPDF_DEB"
  wkhtmltopdf --version 2>&1 | grep -q "patched qt" \
    && success "wkhtmltopdf installed: $(wkhtmltopdf --version 2>&1 | head -1)" \
    || warn "wkhtmltopdf installed without patched qt — PDF generation may fail"
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 7 — frappe system user
# v16 addition: sudoers.d NOPASSWD entry — bench setup production runs ansible
# internally which needs passwordless sudo. Without it, bench setup production
# hangs waiting for a sudo password.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 7 — frappe system user"
step "PHASE 7 — System user: ${FRAPPE_USER}"

if id "$FRAPPE_USER" &>/dev/null; then
  success "User '${FRAPPE_USER}' already exists"
else
  adduser --disabled-password --gecos "" "$FRAPPE_USER"
  success "User '${FRAPPE_USER}' created"
fi

echo "${FRAPPE_USER}:${FRAPPE_USER_PASS}" | chpasswd
usermod -aG sudo "$FRAPPE_USER"

# NOPASSWD sudoers entry — required for bench setup production (ansible internals)
echo "${FRAPPE_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/frappe
chmod 0440 /etc/sudoers.d/frappe
success "User '${FRAPPE_USER}' configured with sudo NOPASSWD (needed for bench setup production)"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 8 — bench CLI + ansible pre-install
# v16 issue: Ubuntu 22.04 ships Python 3.12 alongside 3.10.
# Python 3.12+ marks system Python as "externally managed" (PEP 668).
# pip3 install without --break-system-packages fails with:
#   error: externally-managed-environment
# bench setup production also internally runs: sudo pip install ansible
# Pre-installing ansible here prevents that from failing at Phase 12.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 8 — bench CLI + ansible"
step "PHASE 8 — bench CLI + ansible (PEP 668 handled)"

# Ubuntu 22.04 ships Python 3.12 and Ubuntu 24.04 ships Python 3.12+ — both have
# PEP 668 active. Always use --break-system-packages on this script's target OS.
info "Installing frappe-bench and ansible with --break-system-packages (PEP 668 — Ubuntu 22.04/24.04)"
pip3 install -q frappe-bench --break-system-packages
pip3 install -q ansible --break-system-packages

# Ensure bench is findable in PATH for frappe user
FRAPPE_BASHRC="/home/${FRAPPE_USER}/.bashrc"
grep -q "/.local/bin" "$FRAPPE_BASHRC" 2>/dev/null \
  || echo 'export PATH=$PATH:$HOME/.local/bin:/usr/local/bin' >> "$FRAPPE_BASHRC"

BENCH_VER=$(bench --version 2>/dev/null || echo "installed")
ANSIBLE_VER=$(ansible --version 2>/dev/null | head -1 || echo "installed")
success "bench ${BENCH_VER} ready"
success "ansible pre-installed: ${ANSIBLE_VER}"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 9 — bench init
# v16 critical: must pass --python python3.14
# Without this, bench uses system default Python 3.10 which cannot build Frappe v16.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 9 — bench init"
step "PHASE 9 — bench init (Frappe ${FRAPPE_BRANCH}, Python 3.14)"

if [[ -d "$BENCH_DIR" ]]; then
  warn "Bench directory already exists — skipping init (delete ${BENCH_DIR} to start fresh)"
else
  info "Cloning Frappe v16 + setting up virtualenv with Python 3.14 (3–6 min)..."
  info "bench init checks: redis-server binary, Node v24, pkg-config, Python 3.14..."
  as_frappe "bench init --frappe-branch ${FRAPPE_BRANCH} ${BENCH_DIR} --python python3.14"
  success "Bench initialised at ${BENCH_DIR}"
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 10 — Download ERPNext (and optionally HRMS) app
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 10 — Download ERPNext app"
step "PHASE 10 — Download ERPNext app"

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
# PHASE 11 — Create site
# v16 changes:
#   --mariadb-root-password → --db-root-password (flag renamed in v16)
#   --no-mariadb-socket     → DEPRECATED, use --mariadb-user-host-login-scope='%'
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 11 — Create site"
step "PHASE 11 — Create site: ${SITE_NAME}"

if [[ -d "${BENCH_DIR}/sites/${SITE_NAME}" ]]; then
  success "Site '${SITE_NAME}' already exists — skipping creation"
else
  info "Creating site '${SITE_NAME}' (initialises MariaDB database + site_config.json)..."
  # Passwords passed via env vars — safe for special characters
  # --db-root-password replaces --mariadb-root-password in v16
  # --mariadb-user-host-login-scope='%' replaces deprecated --no-mariadb-socket
  sudo -u "$FRAPPE_USER" \
    ERP_DB_PASS="${DB_ROOT_PASS}" ERP_ADMIN_PASS="${ADMIN_PASS}" ERP_SITE="${SITE_NAME}" \
    bash -l -c "cd ${BENCH_DIR} && bench new-site \"\$ERP_SITE\" \
      --db-root-password \"\$ERP_DB_PASS\" \
      --admin-password \"\$ERP_ADMIN_PASS\" \
      --mariadb-user-host-login-scope='%'"
  success "Site '${SITE_NAME}' created"
fi

# Set default site BEFORE install-app — required in v16
as_frappe_bench "bench use ${SITE_NAME}"
success "Default site set to '${SITE_NAME}' (required before install-app in v16)"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 12 — Install apps on site
# v16 new behaviour: ERPNext's after_install hook pushes background jobs to
# Redis Queue during installation. If Redis Queue is not running, install fails:
#   Error 111 connecting to 127.0.0.1:11000. Connection refused.
# Fix: start bench in background before running install-app.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 12 — Install ERPNext on site"
step "PHASE 12 — Install ERPNext on site (5–15 min)"

info "Starting bench processes in background (v16 requires Redis during install-app)..."
as_frappe_bench "bench start > /tmp/bench_start.log 2>&1 &"
sleep 10  # wait for Redis workers to initialise
info "Bench processes started. Installing ERPNext..."

as_frappe_bench "bench --site ${SITE_NAME} install-app erpnext"
success "ERPNext installed on '${SITE_NAME}'"

if [[ "$INSTALL_HRMS" == true ]]; then
  info "Installing HRMS..."
  as_frappe_bench "bench --site ${SITE_NAME} install-app hrms"
  success "HRMS installed"
fi

# Stop background bench — production setup takes over process management
info "Stopping background bench (supervisor will manage processes from now on)..."
pkill -f "bench start" 2>/dev/null || true
sleep 3

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 13 — Build frontend assets (v16 CRITICAL step)
# v16 assets use content-hashed filenames (desk.bundle.XXXXXXXX.css).
# bench setup production does NOT build assets automatically.
# Without this step, Nginx returns 404/403 on all /assets/ paths — no CSS/JS.
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 13 — Build frontend assets"
step "PHASE 13 — Build frontend assets"

info "Building ERPNext frontend assets (yarn + webpack, 3–8 min)..."
as_frappe_bench "bench build"
success "Frontend assets built"

# Verify built assets exist
ASSET_COUNT=$(find "${BENCH_DIR}/sites/assets" -name "*.css" -o -name "*.js" 2>/dev/null | wc -l)
info "Assets on disk: ${ASSET_COUNT} files"
[[ "$ASSET_COUNT" -gt 0 ]] \
  && success "Asset build verified" \
  || warn "No CSS/JS assets found — bench build may have failed. Check ${LOG_FILE}"

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 14 — Production setup (Nginx + Supervisor)
# ════════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE="PHASE 14 — Production setup (Nginx + Supervisor)"
step "PHASE 14 — Production setup"

info "Generating Nginx + Supervisor configs via bench..."
env PATH="$PATH:/usr/local/bin:/home/${FRAPPE_USER}/.local/bin" \
  bench setup production "$FRAPPE_USER" --yes

# CRITICAL: bench setup production writes supervisor config to bench-local config/
# but does NOT always symlink to /etc/supervisor/conf.d/ automatically.
# Without this, supervisord starts empty — no web, no workers, no scheduler.
info "Ensuring supervisor config symlink exists..."
ln -sf "${BENCH_DIR}/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf

# Full daemon restart first — prevents CANT_REREAD conflict on some Ubuntu versions
systemctl restart supervisor
sleep 3
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

# Remove default Nginx site — it intercepts all requests before frappe config
[[ -f /etc/nginx/sites-enabled/default ]] && rm /etc/nginx/sites-enabled/default \
  && info "Removed default Nginx site"

# Symlink frappe-bench nginx config if bench wrote it to sites-available
# v16 bench may write to sites-available instead of conf.d depending on version
if [[ -f /etc/nginx/sites-available/frappe-bench && \
      ! -f /etc/nginx/sites-enabled/frappe-bench ]]; then
  ln -sf /etc/nginx/sites-available/frappe-bench /etc/nginx/sites-enabled/frappe-bench
  info "Symlinked frappe-bench Nginx config from sites-available"
fi

nginx -t && systemctl reload nginx
systemctl enable supervisor nginx
success "Nginx reloaded and supervisor enabled on boot"

info "Waiting for all processes to start..."
sleep 5
info "Supervisor process status:"
supervisorctl status || true

# Verify Nginx can actually serve assets (post-chmod check)
ASSET_SAMPLE=$(find "${BENCH_DIR}/sites/assets" -name "*.css" 2>/dev/null | head -1)
if [[ -n "$ASSET_SAMPLE" ]]; then
  ASSET_PATH="${ASSET_SAMPLE#${BENCH_DIR}/sites}"
  HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "http://localhost${ASSET_PATH}" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    success "Nginx serving assets: HTTP 200 on ${ASSET_PATH}"
  else
    warn "Asset serving returned HTTP ${HTTP_CODE} for ${ASSET_PATH}"
    warn "If assets return 404, add alias to Nginx config:"
    warn "  sudo nano /etc/nginx/conf.d/frappe-bench.conf"
    warn "  Change: location /assets { try_files \$uri =404; }"
    warn "  To:     location /assets { alias ${BENCH_DIR}/sites/assets; try_files \$uri =404; }"
    warn "  Then: sudo nginx -t && sudo systemctl reload nginx"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 15 — Domain mapping (if provided)
# ════════════════════════════════════════════════════════════════════════════════
if [[ -n "$DOMAIN" ]]; then
  CURRENT_PHASE="PHASE 15 — Domain mapping"
  step "PHASE 15 — Domain: ${DOMAIN}"

  as_frappe_bench "bench setup add-domain ${DOMAIN} --site ${SITE_NAME}"
  nginx -t && systemctl reload nginx
  success "Domain '${DOMAIN}' → site '${SITE_NAME}'"

  sudo -u "$FRAPPE_USER" bash -l -c \
    "cd ${BENCH_DIR} && bench --site ${SITE_NAME} set-config host_name 'https://${DOMAIN}'" 2>/dev/null || true

  # ─── SSL ─────────────────────────────────────────────────────────────────────
  if [[ "$SKIP_SSL" == false ]]; then
    CURRENT_PHASE="PHASE 16 — SSL (Let's Encrypt)"
    step "PHASE 16 — SSL (Let's Encrypt)"

    snap install --classic certbot 2>/dev/null || true
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true

    SERVER_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
    info "Server public IP: ${SERVER_IP}"
    info "Ensure DNS A record: ${DOMAIN} → ${SERVER_IP} before SSL issuance"

    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}"; then
      nginx -t && systemctl reload nginx
      success "SSL certificate issued for ${DOMAIN}"
      warn "IMPORTANT: Never run 'bench setup nginx' after certbot — it wipes SSL config."
      warn "For Nginx changes, always edit /etc/nginx/conf.d/frappe-bench.conf directly."
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
echo -e "${BOLD}${GREEN}  ERPNext v16 Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}URL         :${NC} ${ACCESS_URL}"
echo -e "  ${BOLD}Login       :${NC} Administrator"
echo -e "  ${BOLD}Password    :${NC} (value you entered for ERPNext admin)"
echo -e "  ${BOLD}Site name   :${NC} ${SITE_NAME}"
echo -e "  ${BOLD}Python      :${NC} 3.14"
echo -e "  ${BOLD}Node.js     :${NC} $(node -v)"
echo -e "  ${BOLD}Bench dir   :${NC} ${BENCH_DIR}"
echo -e "  ${BOLD}Install log :${NC} ${LOG_FILE}"
echo ""
echo "  Useful commands:"
echo "  → Process status  : sudo supervisorctl status"
echo "  → Live logs       : tail -f ${BENCH_DIR}/logs/*.log"
echo "  → Backup          : cd ${BENCH_DIR} && bench --site ${SITE_NAME} backup"
echo "  → Update          : cd ${BENCH_DIR} && bench update"
echo "  → Rebuild assets  : cd ${BENCH_DIR} && bench build"
echo ""
echo -e "  ${YELLOW}v16 reminders:${NC}"
echo "  → If supervisor shows FATAL/STOPPED:"
echo "    sudo systemctl restart supervisor && sudo supervisorctl reread && sudo supervisorctl update"
echo "  → If assets return 404 after deploy, run: bench build"
echo "  → Never run 'bench setup nginx' after SSL is set up (wipes certbot config)"
echo ""
