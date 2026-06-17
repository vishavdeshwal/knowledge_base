# Incident: PostgreSQL Extension Cryptominer + Credential Exfiltration — iof3208 (107.178.113.26)

**Date:** 2026-06-11
**Server:** iof3208, 107.178.113.26, port 1022, Ubuntu 24.04
**Severity:** Critical — credential exfiltration + cryptominer across multiple Docker containers
**Duration:** Breach ~May 11 (first exfil) → cleaned June 11 (~1.5 hours active remediation)
**Related Incident:** [iof3208-xmrig-cryptominer-2026-05-08.md](iof3208-xmrig-cryptominer-2026-05-08.md) — same server, same user, prior attack

---

## Executive Summary

A second, significantly more sophisticated compromise of server iof3208. The attacker:

1. Re-entered via the `udc` user (same vector as the May 8 incident — SSH credentials not fully rotated after the prior breach)
2. Ran credential-exfiltration scripts on **May 11** and **May 19**, stealing AWS keys, GCP service account JSON, all SSH private keys, auth tokens, and app environment variables
3. Injected a **malicious PostgreSQL shared library** (`gcmanager-1.so`) into the data volumes of two Saleor e-commerce postgres containers, which survived container restarts
4. The library spawned XMRig cryptominers disguised as legitimate kernel and postgres process names
5. Multiple watchdog layers ensured automatic respawning when miners were killed

---

## Attack Timeline

| Date | Event |
|------|-------|
| ~May 08 | Prior XMRig incident cleaned — but credentials not rotated, SSH password auth not fully disabled |
| ~May 11 | Attacker re-enters via `udc` user. Drops and executes `/tmp/.e08c06312.sh` (credential exfiltration) |
| May 11 14:05–14:09 | Exfiltration script runs — steals credentials, keys, tokens, sends to `144.172.116.48:8080` |
| ~May 19 | Second exfiltration run via `/tmp/.ed64f75cd.sh` — updated harvest, same exfil server |
| ~Jun 08 | Postgres containers (medusa + alive-wellness Saleor) infected with `gcmanager-1.so` extension |
| Jun 11 | Mining detected (CPU at 1720%+) → incident response begins |
| Jun 11 08:14 | Server fully cleaned, both containers restored |

---

## Root Cause

**Primary:** The `udc` Linux user (uid 1014) was re-compromised after the May 8 incident because credentials were not rotated and SSH password authentication remained enabled.

**Secondary:** The `udc` user has `sudo` and `docker` group membership, giving the attacker full Docker access. This allowed injection of malicious files directly into Docker volume directories on the host.

---

## Attack Anatomy

### Phase 1 — Credential Exfiltration (May 11 and May 19)

The attacker dropped shell scripts into `/tmp/` as hidden files, executed them, and exfiltrated results to a remote HTTP server.

**Script locations:**
- `/tmp/.e08c06312.sh` (May 11) — executed as `udc` user
- `/tmp/.ed64f75cd.sh` (May 19) — second run, updated harvest
- Results staged in `/tmp/.e08c06312/` and `/tmp/.ed64f75cd/` respectively

**Script behavior:**
```sh
CB="http://144.172.116.48:8080"   # C2 exfil server
# Collects and HTTP-POSTs each file category separately:
# - /proc/*/environ   → app secrets, API keys
# - ~/.aws/credentials, .env files → AWS access keys
# - GCP service account JSON files → cloud identity
# - ~/.ssh/id_* private keys → SSH access to all connected infra
# - bash history → command patterns, credentials typed in terminal
# - docker inspect output → container env vars, secrets
# - running process cmdlines → application context
```

**Confirmed exfiltrated data:**

| File | Size | Contents |
|------|------|----------|
| `aws_full.txt` | 4,311 bytes | AWS access key IDs and secret keys |
| `gcp_sa_full.txt` | 173,301 bytes | GCP service account private key JSON |
| `privkey.txt` | 637,096 bytes | **All SSH private keys** on the server |
| `tokens.txt` | 376,123 bytes | Auth tokens, bearer tokens, API keys |
| `environ.txt` | 29,607 bytes | All process environment variables |
| `docker.txt` | 50,025 bytes | Docker container inspect output (env vars) |
| `cmdline.txt` | 182,998 bytes | All running process command lines |
| `found.txt` | 40,367 bytes | Credential strings matched by regex |
| `history.txt` | 718 bytes | Bash history |

> **Note:** `privkey.txt` at 637KB is extremely large — this server hosts many client apps with separate Linux users, each potentially having SSH keys. All of them are compromised.

---

### Phase 2 — Cryptominer via Malicious PostgreSQL Extension

#### Infection Mechanism

The attacker injected a malicious shared library (`gcmanager-1.so`) directly into the PostgreSQL data volume directories on the host:

```
/var/lib/docker/volumes/saleor-platform_saleor-db/_data/gcmanager-1.so
/var/lib/docker/volumes/saleor_saleor-db-alive-wellness/_data/gcmanager-1.so
```

They then modified `postgresql.conf` inside the volume to auto-load the library on every postgres startup:

```ini
# Line 742 of postgresql.conf (injected by attacker)
shared_preload_libraries = '/var/lib/postgresql/data/gcmanager-1.so'
```

**Why this is a highly persistent technique:**
- `shared_preload_libraries` causes postgres to load the `.so` as a **background worker** at startup
- The library runs with postgres privileges immediately before any connection is accepted
- Survives container restarts (the volume persists — only the container's writable layer is reset)
- Survives container recreation — volume data is preserved by default in Docker
- The `.so` file is inside the postgres data directory, which looks like legitimate postgres internals

#### Infected Containers

| Container | Image | Volume | Port |
|-----------|-------|--------|------|
| `saleor-platform-db-1` | `postgres:15` | `saleor-platform_saleor-db` | 55432 |
| `alive-wellness-saleor-db-1` | `postgres:15-alpine` | `saleor_saleor-db-alive-wellness` | 5434 |

Both containers belong to Saleor e-commerce platform deployments on the server.

#### What gcmanager-1.so Did

On every postgres startup, the library:
1. Created a hidden working directory in `/var/tmp/` with a random name (e.g., `/var/tmp/.mzekomwefj/`, `/var/tmp/.tmtkvscqnp/`, `/var/tmp/.urhtakngky/`, `/var/tmp/.oxudwjwlap/`)
2. Dropped a self-contained XMRig binary with a random name (e.g., `ejziqouqlv`, `rltunreijg`, `vedmatbpaq`)
3. Executed the miner binary, then **deleted itself and the directory** (anti-forensics)
4. Spawned a watchdog process to respawn the miner if killed

#### Process Disguise Technique

The malware masqueraded as legitimate system and postgres processes:

| Fake Process Name | Real Binary | PID |
|---|---|---|
| `postgres: walwriter` | `/var/tmp/.mzekomwefj/ejziqouqlv` | 1472518 |
| `postgres: checkpointer` | `/var/tmp/.oxudwjwlap/exjguwplup` | 1855897 |
| `postgres: autovacuum launcher` | `/var/tmp/.urhtakngky/vedmatbpaq` | 1855333 |
| `[kworker/5:1-events]` | `/usr/bin/zdumplogname` | 1846183 |
| `[migration/5]` | `/usr/bin/prlimitlogger` | 1820823 |
| `/sbin/wpa_supplicant -u -s ...` | `/usr/bin/statclusterdb` | 1416279 |

**How to detect the disguise:** Real kernel threads (`[kworker/...]`, `[migration/...]`) have zero RSS memory. Any such process with >1MB RAM is malware. Always verify with `/proc/<PID>/exe`.

#### Mining Configuration (from recovered `config.json`)

```json
{
  "cpu": { "enabled": true, "max-threads-hint": 90, "throttle": 0 },
  "randomx": { "mode": "auto" },
  "pools": [{
    "algo": "rx/0",
    "url": "185.132.53.73:443",
    "user": "NEuFOFA22222k",
    "tls": true,
    "nicehash": true
  }]
}
```

- Algorithm: **RandomX (rx/0)** — Monero (XMR)
- Pool: `185.132.53.73:443` — uses port 443 (HTTPS) to blend with normal traffic
- CPU throttle: 0 (uses all available cores, hence 1700%+ CPU)

#### Watchdog Architecture

The malware had a multi-layer process tree to ensure respawning:

```
containerd-shim (Docker host)
└── postgres master (inside container, legitimate binary)
    ├── [legitimate postgres workers]
    └── [watchdog binary] ← dropped by gcmanager-1.so
        └── [miner binary] ← actual XMRig, random name
```

When the miner was killed, the watchdog spawned a new one with a new random name and directory within seconds. Killing the watchdog caused the `gcmanager-1.so` (loaded in the postgres process) to spawn a new watchdog. Only removing the `.so` file and fixing `postgresql.conf` broke the chain permanently.

#### Additional Host-Level Binaries (self-deleted)

These were dropped into `/usr/bin/` and self-deleted after launch:
- `/usr/bin/statclusterdb` — root-level watchdog
- `/usr/bin/prlimitlogger` — miner instance
- `/usr/bin/zdumplogname` — miner instance

Self-deletion is confirmed when `/proc/<PID>/exe` resolves to a path but the file no longer exists on disk.

---

## Indicators of Compromise (IOCs)

### Network IOCs

| Type | Value | Purpose |
|------|-------|---------|
| IP | `185.132.53.73:443` | XMRig mining pool (Monero) |
| IP | `144.172.116.48:8080` | Credential exfiltration C2 |
| Wallet | `NEuFOFA22222k` | Attacker Monero wallet |

### File IOCs

| Path | Description |
|------|-------------|
| `<pg_data_dir>/gcmanager-1.so` | Malicious PostgreSQL background worker |
| `postgresql.conf` line: `shared_preload_libraries = '...gcmanager-1.so'` | Persistence config |
| `/var/tmp/.<random8chars>/` | Hidden miner working directory |
| `/var/tmp/systemd-logind` | XMRig binary (disguised as systemd service) |
| `/var/tmp/cpu-logind` | XMRig binary |
| `/var/tmp/system-check` | XMRig binary |
| `/var/tmp/config.json` | XMRig pool configuration |
| `/tmp/.<hexid>.sh` | Credential exfiltration script |
| `/tmp/.<hexid>/` | Exfiltrated data staging directory |

### Process IOCs

| Indicator | How to detect |
|-----------|--------------|
| `postgres: <worker>` with non-postgres exe path | `ls -la /proc/<PID>/exe` |
| `[kworker/...]` or `[migration/...]` with RSS > 0 | `ps aux` — kernel threads have 0 RSS |
| Any process in `/var/tmp/` | `ls /proc/*/exe 2>/dev/null \| xargs -I{} readlink {} \| grep /var/tmp` |
| High CPU from postgres worker process | `ps aux --sort=-%cpu \| head` |

---

## Remediation Steps

### Step 1 — Forensic Snapshot (before touching anything)

```bash
# Identify processes by their real binary, not displayed name
for pid in $(ps aux | awk 'NR>1{print $2}'); do
    exe=$(readlink /proc/$pid/exe 2>/dev/null)
    [[ "$exe" == *"/var/tmp/."* || "$exe" == *"/tmp/."* ]] && \
        echo "SUSPICIOUS PID:$pid EXE:$exe CMD:$(ps -o args= -p $pid)"
done

# Check kernel thread impersonators
ps aux | awk '$11 ~ /^\[/ && $6 > 1000 {print "FAKE KERNEL THREAD:", $0}'

# Find all hidden dirs in /var/tmp
ls -la /var/tmp/ | grep '^\.'
```

### Step 2 — Find Persistence Before Killing Anything

```bash
# Check all crontabs
for user in $(cut -d: -f1 /etc/passwd); do
    out=$(crontab -u $user -l 2>/dev/null)
    [ -n "$out" ] && echo "=== $user ===" && echo "$out"
done

# Check postgres data volumes for malicious extension
find /var/lib/docker/volumes -name 'gcmanager-1.so' 2>/dev/null

# Check postgresql.conf in all postgres volumes
find /var/lib/docker/volumes -name 'postgresql.conf' 2>/dev/null | \
    xargs grep -l 'gcmanager\|var/tmp\|/tmp/' 2>/dev/null

# Check /usr/bin for recently added files
find /usr/bin -newer /usr/bin/ls -type f 2>/dev/null
```

### Step 3 — Remove Persistence

```bash
# 3a. Clear infected crontabs
crontab -u udc -r

# 3b. Remove malicious extension from ALL postgres volumes
find /var/lib/docker/volumes -name 'gcmanager-1.so' -exec rm -f {} \; -print

# 3c. Fix postgresql.conf in each infected volume
# Find the line number first:
grep -n shared_preload_libraries <pg_data_dir>/postgresql.conf

# Fix it (replace line N with empty value):
sed -i "Ns/.*/shared_preload_libraries = ''\\t# cleaned/" <pg_data_dir>/postgresql.conf

# 3d. Remove malware files from /var/tmp and /tmp
rm -rf /var/tmp/systemd-logind /var/tmp/cpu-logind /var/tmp/system-check /var/tmp/config.json
rm -rf /tmp/.<hexid>.sh /tmp/.<hexid>/
```

### Step 4 — Kill All Malware Processes

Kill persistence **first**, then processes — otherwise they respawn instantly.

```bash
# Kill all processes with exe in hidden /var/tmp dirs
for pid in $(ls /proc/ | grep '^[0-9]'); do
    exe=$(readlink /proc/$pid/exe 2>/dev/null)
    [[ "$exe" == *"/var/tmp/."* ]] && kill -9 $pid && echo "Killed $pid: $exe"
done

# Kill known watchdog PIDs
kill -9 <watchdog_pid> <miner_pid>
```

### Step 5 — Recreate Infected Containers

Since the `.so` file is removed and `postgresql.conf` is fixed, a restart is sufficient. Recreate to also clear the container's writable layer:

```bash
# medusa Saleor
cd /home/medusa/saleor-platform
docker compose stop db && docker compose rm -f db && docker compose up -d db

# alive-wellness Saleor (note: needs explicit project name to avoid collision)
docker stop alive-wellness-saleor-db-1 && docker rm alive-wellness-saleor-db-1
cd /home/alive-wellness/saleor-platform
docker compose -p alive-wellness-saleor up -d db
```

### Step 6 — Block Attacker IPs

```bash
iptables -A OUTPUT -d 185.132.53.73 -j DROP   # mining pool
iptables -A OUTPUT -d 144.172.116.48 -j DROP   # exfil C2
iptables-save > /etc/iptables/rules.v4
```

### Step 7 — Verify Clean

```bash
# No processes running from hidden dirs
ls /proc/*/exe 2>/dev/null | while read f; do
    t=$(readlink $f 2>/dev/null)
    echo "$t" | grep -qE '/var/tmp/\.|/tmp/\.' && echo "STILL RUNNING: $f -> $t"
done

# No gcmanager in any volume
find /var/lib/docker/volumes -name 'gcmanager-1.so' 2>/dev/null || echo 'clean'

# CPU back to normal
ps aux --sort=-%cpu | head -5

# Containers running healthy
docker ps | grep -E 'saleor-platform-db|alive-wellness-saleor-db'
```

---

## Why Simple Container Restart Didn't Work

This is the key lesson from this incident. The infection was **in the Docker volume, not the container layer**.

```
Docker Container (writable layer)  ← docker rm clears this
        ↓ mounts
Docker Volume (persistent)         ← docker rm does NOT clear this
  /var/lib/postgresql/data/
    postgresql.conf                ← modified by attacker
    gcmanager-1.so                 ← malware, auto-loaded at startup
```

**First attempt:** `docker compose stop db && docker compose rm -f db && docker compose up -d db`
- Result: Container recreated from clean `postgres:15` image
- But: The old volume was re-attached
- Result: `gcmanager-1.so` loaded on startup → miners respawned within 3 minutes

**Correct fix:**
1. Remove `gcmanager-1.so` from the volume on the host
2. Fix `postgresql.conf` in the volume on the host
3. Then restart the container

The data volume itself was not wiped — only the malware files within it were removed. The application database data was fully preserved.

---

## Post-Incident Actions Required

### Immediate (do now)

- [ ] **Rotate all AWS credentials** — `aws_full.txt` (4.3KB) was exfiltrated. Rotate access keys in IAM for any user whose key was on this server
- [ ] **Revoke all GCP service account keys** — `gcp_sa_full.txt` (173KB) exfiltrated. Revoke in GCP IAM → Service Accounts for each affected SA
- [ ] **Rotate all SSH keys** — `privkey.txt` (637KB) exfiltrated. All private keys on this server must be considered compromised. Revoke from `authorized_keys` on all downstream servers
- [ ] **Rotate all app secrets** — `environ.txt`, `tokens.txt`, `docker.txt` exfiltrated. Rotate DB passwords, JWT secrets, API keys for every app running on this server
- [ ] **Disable SSH password auth permanently:**
  ```bash
  sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config.d/hardening.conf
  sshd -t && systemctl reload sshd
  ```
- [ ] **Lock `udc` user password:**
  ```bash
  passwd -l udc
  ```

### Within 24 Hours

- [ ] Audit auth logs to find the re-entry point:
  ```bash
  grep -E 'Accepted|Failed.*udc' /var/log/auth.log | grep -v 'Jun 11' | tail -100
  ```
- [ ] Audit `udc` user's sudo and docker access — restrict if not needed:
  ```bash
  # Review groups
  groups udc
  # Docker access gives effective root — remove if udc doesn't need it
  gdeluser udc docker
  ```
- [ ] Install fail2ban:
  ```bash
  apt install fail2ban -y
  cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
  # Set maxretry=3, bantime=3600 for sshd
  systemctl enable --now fail2ban
  ```
- [ ] Scan ALL other postgres container volumes for `gcmanager-1.so`:
  ```bash
  find /var/lib/docker/volumes -name 'gcmanager-1.so' 2>/dev/null
  find /var/lib/docker/volumes -name 'postgresql.conf' 2>/dev/null | \
      xargs grep -l 'gcmanager' 2>/dev/null
  ```
- [ ] Make iptables rules persistent:
  ```bash
  apt install iptables-persistent -y
  iptables-save > /etc/iptables/rules.v4
  ```

---

## Key Differences from May 8 Incident

| Aspect | May 8 Incident | Jun 11 Incident |
|--------|---------------|-----------------|
| Entry vector | SSH brute-force | Re-entry via same `udc` user (prior creds not rotated) |
| Persistence | Crontab `@reboot` + watchdog shell script | Malicious PostgreSQL `.so` extension in Docker volume |
| Disguise | Fake Next.js process names | Fake kernel threads + fake postgres worker names |
| Anti-forensics | Binary deleted after launch | Same + randomized directory/binary names on every spawn |
| Scope | Host-only | Host + inside Docker containers |
| Additional payload | Mining only | **Credential exfiltration** (AWS, GCP, SSH keys, all secrets) |
| Cleanup difficulty | Medium — remove files, kill processes | High — required identifying Docker volume infection |

---

## Lessons Learned

1. **Credential rotation after a breach is not optional.** The Jun 11 incident is a direct consequence of not rotating `udc` credentials after May 8.

2. **Docker volumes persist through container recreation.** Malware that targets the data volume (not the container layer) survives `docker rm` + `docker run`. Always inspect volumes when a container behaves unexpectedly after recreation.

3. **Always verify process identity via `/proc/<PID>/exe`.** `ps aux` shows what the process *claims* to be. The exe symlink shows what it *actually* is. These will differ for any masquerading malware.

4. **Kernel threads have zero RSS.** Any `[kworker/...]` or `[migration/...]` process with RAM usage > 0 is malware.

5. **PostgreSQL `shared_preload_libraries` is a powerful persistence vector.** Any attacker with write access to the postgres data directory can achieve code execution on every startup by placing a `.so` file and modifying `postgresql.conf`.

6. **`sudo` + `docker` group access = effective root.** The `udc` user's docker group membership allowed the attacker to write directly into Docker volume paths (which require root) by operating as the `udc` user with docker socket access. Audit who has docker group membership.

7. **Kill persistence before killing processes.** If you kill the miner without first removing `gcmanager-1.so` and fixing `postgresql.conf`, postgres auto-loads the library again on restart and spawns a new miner within seconds.

---

## Cross-Client Learning

This attack pattern targets **any server running PostgreSQL containers with Docker volumes** where an attacker has gained write access to the host's Docker volume directories.

Check all servers where:
- Docker is running with PostgreSQL containers
- Any user with `docker` group access was compromised
- The postgres data directory is a named or bind-mounted volume

Verification command (run on any server with postgres containers):
```bash
find /var/lib/docker/volumes -name 'postgresql.conf' -exec \
    grep -l 'shared_preload_libraries.*\.so' {} \;
```

---

## Reference

- **Exfil C2:** `http://144.172.116.48:8080`
- **Mining pool:** `185.132.53.73:443` (RandomX/Monero)
- **Wallet:** `NEuFOFA22222k`
- **Malicious library:** `gcmanager-1.so` (565,920 bytes, placed in postgres data dir)
- **Prior incident:** [iof3208-xmrig-cryptominer-2026-05-08.md](iof3208-xmrig-cryptominer-2026-05-08.md)
