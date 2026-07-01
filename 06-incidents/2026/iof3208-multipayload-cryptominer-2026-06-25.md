# Incident: Multi-Payload Cryptominer/Monetization Malware — iof3208 (107.178.113.26)

**Date:** 2026-06-25
**Server:** iof3208, 107.178.113.26, port 1022
**Severity:** Critical — root-level rootkit + multi-payload monetization malware in production Postgres container
**Related incidents:** [iof3208-xmrig-cryptominer-2026-05-08.md](iof3208-xmrig-cryptominer-2026-05-08.md), [iof3208-postgres-extension-miner-exfil-2026-06-11.md](iof3208-postgres-extension-miner-exfil-2026-06-11.md) — third compromise of this server in under 2 months.

---

## Executive Summary

Third compromise of this server. Unlike the prior two incidents (SSH brute force, then stolen-credential re-entry + `shared_preload_libraries` injection), this round shows a **different entry vector**: the `shared_preload_libraries` fix from June 11 was still intact, yet malware was running again in the same container (`saleor-platform-db-1`). Root cause is most likely the Postgres container's **publicly exposed port (55432)**, not SSH at all.

A multi-payload "monetization bundle" was running, not just a miner:
- A persistent remote-access/tunnel backdoor (`cli start accept --token ...`)
- Two passive-income/bandwidth-monetization agents abused for profit (EarnFM, Bitping)
- A fake `postgres checkpointer` process (XMRig-style disguise)
- A fake `systemd-udevd` process running as root (790% CPU, 2GB RAM)
- A rootkit hiding all of the above from `ps`/`top` run **inside** the container (replaced `/usr/bin/.local/bin/{ldd,top}`), invisible to `docker exec ... ps -ef` but visible via `docker top` from the host (host's `/proc` walk bypasses the in-container hook).

## Key Discovery: Network Exposure, Not Just Credentials

**`iptables -A INPUT ... -j DROP` rules on Docker-published ports do not work.** Docker publishes container ports via DNAT in the `nat` table + the `FORWARD` chain, not `INPUT`. An `INPUT` DROP rule for a published port is a false sense of security — it never sees the traffic.

Verified externally reachable on this server (confirmed via direct `nc` test from outside):

| Port | DNAT target | Likely owner |
|---|---|---|
| 55432 | 172.19.0.4:5432 | saleor-platform |
| 35432 | 172.20.0.2:5432 | unidentified |
| 5435 | 172.25.0.2:5432 | unidentified |
| 25434 | 192.168.32.4:5432 | unidentified |
| 15432 | 192.168.48.4:5432 | unidentified |
| 25432 | 192.168.32.8:5432 | unidentified |
| 25433 | 192.168.32.10:5432 | unidentified |
| 5433 | 192.168.160.2:5432 | unidentified |
| 5434 | 192.168.128.5:5432 | alive-wellness saleor (per June 11 incident) |
| 5439 | 172.28.0.2:5432 | unidentified |

**All 10 Postgres containers on this host are reachable from the public internet.** Any one with a weak/default/leaked password is a viable entry point via Postgres RCE techniques (`COPY ... TO PROGRAM`, `lo_import`, malicious extensions) — no SSH access needed. This explains why the June 11 fix (cleaning `shared_preload_libraries`) didn't prevent recurrence: the attacker doesn't need that vector if they can talk to Postgres directly and have valid/weak DB credentials.

## IOCs

### Process IOCs (all under container `saleor-platform-db-1`, PPID = container's PID 1)

| Disguised name | Real binary | Path | Notes |
|---|---|---|---|
| `/lib/systemd/systemd-udevd` (root) | `debconf-set-selectionsshasum` | `/usr/bin/` (self-deleted) | 790% CPU, 2GB RAM |
| `postgres checkpointer` | `postgres` | `/tmp/.perf.c/` (self-deleted) | |
| `cli start accept --token ...` | `cli` | `/tmp/.t.trf/` (self-deleted) | tunnel/backdoor, token-based |
| `earnfm_example` | EarnFM agent | `/var/.e.efm/` (self-deleted) | bandwidth monetization abuse |
| `bitpingd` | Bitping agent | `/var/.b.bpn/` (self-deleted) | bandwidth monetization abuse |
| musl-loaded node app | `node app/dist/index.js` | `/var/.r.rpk/` (self-deleted) | payload unidentified |
| `/usr/sbin/cupsd -l` | `/usr/bin/dash` (argv spoofed) | cwd `/tmp` | likely watchdog/shell, no children at kill time, one open socket fd |

### File IOCs

- `/tmp/.apid` — 6-byte pidfile
- `/tmp/ccrl` — 4.5MB executable, the dropper (ran once at container start, exited, left on disk)
- `/usr/bin/.local/bin/ldd`, `/usr/bin/.local/bin/top` — rootkit-replaced utilities, hide malware from in-container `ps`/`top`
- `/usr/lib/exi`, `/usr/lib/vei` — unidentified, removed
- `/var/spool/lpd/.ssh/authorized_keys` — planted SSH key for `lp@localhost` (`lp` user), inert since no sshd present in this container — possibly a generic implant-pack artifact unrelated to this specific exploitation chain

### Naming pattern

`/var/.<letter>.<3-char-abbrev>/` and `/tmp/.<3-char-abbrev>/` — hidden, randomly-initialed staging dirs, unlinked immediately after exec (anti-forensics, same technique as June 11 incident but new directory convention).

## False Lead

Repeated root SSH pubkey logins from `104.28.155.88` every 2–8 minutes were initially suspected as attacker re-entry (matches the June 11 incident's "rotate SSH keys" unfinished action item). **User confirmed this is a legitimate office IP** (MacBook-Pro-2) — likely VS Code Remote-SSH or similar tooling creating frequent short-lived control connections. No SSH keys were touched or removed this incident. Do not assume frequent root reconnects = compromise without checking with the user first.

## Remediation Taken

1. Identified all malware processes via host-side `/proc/<pid>/exe` (bypasses in-container rootkit hiding) and `docker top` (reads host process table directly, unaffected by in-container `ps`/`top` replacement).
2. Killed all 7 malware PIDs directly via host `kill -9` (not `docker exec`, since in-container tools are compromised).
3. Waited 15s, re-swept for hidden-path processes — nothing respawned, confirming no live watchdog cron/script outside the killed processes.
4. Cleaned dropped files inside the container: `/tmp/.apid`, `/tmp/ccrl`, rootkit-replaced `ldd`/`top`, `/usr/lib/exi`/`vei`, planted `lp` SSH key.
5. Verified no lateral spread: scanned all other running containers and host-wide filesystem for the same binary names/hidden-dir patterns — none found.
6. Confirmed `gcmanager-1.so` (June 11 vector) still absent from all postgres volumes — that fix held.
7. Did **not** touch the container lifecycle (left `saleor-platform-db-1` running, per user's choice, to avoid downtime) and did **not** touch `/root/.ssh/authorized_keys` (per user's correction on the office IP).

## Post-Incident Actions Required

### Immediate
- [ ] **Fix the published-port exposure.** `iptables INPUT` rules don't block Docker-published ports — need either: bind Postgres containers to `127.0.0.1` instead of `0.0.0.0` in each `docker-compose.yml`, or add real blocking rules to the `DOCKER-USER` chain (the chain Docker actually consults before forwarding), or front these with a VPN/bastion and remove the public port mappings entirely.
- [ ] Audit and rotate credentials for **all 10** exposed Postgres instances — assume any with weak/default/reused passwords were the actual entry point.
- [ ] Identify the container/client owner for each of the 9 unidentified DNAT ports (35432, 5435, 25434, 15432, 25432, 25433, 5433, 5439) — only 55432 (saleor-platform) and 5434 (alive-wellness, per June 11 report) are currently mapped to known clients.

### Within 24 hours
- [ ] Check Postgres logs on all 10 containers for `COPY ... TO PROGRAM`, `lo_import`, or unexpected `CREATE EXTENSION` statements around the infection window.
- [ ] Decide whether `saleor-platform-db-1` needs a full recreate (not just process kill) — the dropper (`ccrl`) and its unpack mechanism weren't fully traced; a clean recreate from the volume (after confirming the volume itself is clean) would be more thorough if downtime is acceptable.
- [ ] Apply the same hidden-process/rootkit detection sweep (this incident's IOC table) to all other client containers on this host, not just the ones already checked.

## Lessons Learned

1. **`iptables -A INPUT ... dport <published_port> -j DROP` is a no-op for Docker containers.** Must use `DOCKER-USER` chain or bind to `127.0.0.1` instead. This was likely also true during the June 11 incident's "block attacker IPs" step for inbound rules — outbound DROP rules (used there) are unaffected by this gotcha, only inbound port-blocking is.
2. **In-container `ps`/`top` can be rootkit-replaced.** Always cross-check with `docker top` (host-side) when investigating a container — never trust process lists gathered exclusively from inside the container's own namespace.
3. **Don't assume a recurring root-login pattern is the attacker without asking.** Confirmed-legitimate automated tooling (e.g. editor remote-SSH) can look identical to a watchdog reconnect pattern.
4. **A previously-applied fix holding (no `gcmanager-1.so`) doesn't mean the entry vector is closed** — attackers (or unrelated opportunistic actors) adapt to whatever's reachable. Always check exposure (ports, exposed services), not just the last known IOC.

## Cross-Client Learning

Any server hosting multiple Docker Postgres containers with port mappings should be audited for the same `INPUT`-vs-`FORWARD` iptables gotcha. Check with:

```bash
# List all Docker DNAT'd ports (the real exposure surface)
iptables -t nat -L DOCKER -n | grep DNAT

# Test each one externally — INPUT rules alone will NOT show you the truth
nc -zv -w 3 <host_ip> <port>
```

If a port shows as DNAT'd and externally reachable despite an `INPUT` DROP rule, it's exposed. Fix at the source (bind to `127.0.0.1`, remove the port mapping, or use `DOCKER-USER` chain rules) rather than `INPUT`.
