# Playbook: Cryptominer in PostgreSQL Docker Container

**Symptom:** CPU at 1000%+, postgres container children have exe paths in `/var/tmp/.<random>/`
**Root cause pattern:** Malicious `shared_preload_libraries` in postgres data volume
**Reference incident:** [iof3208-postgres-extension-miner-exfil-2026-06-11](../../06-incidents/2026/iof3208-postgres-extension-miner-exfil-2026-06-11.md)

---

## Quick Detection (30 seconds)

```bash
# 1. Are any processes running from hidden /var/tmp dirs?
ls /proc/*/exe 2>/dev/null | while read f; do
    t=$(readlink $f 2>/dev/null)
    echo "$t" | grep -qE '/var/tmp/\.|/tmp/\.' && echo "MALWARE: $(dirname $f | xargs basename) -> $t"
done

# 2. Are any "kernel threads" using RAM? (should be 0)
ps aux | awk '$11 ~ /^\[/ && $6 > 1000 {print "FAKE KERNEL THREAD:", $0}'

# 3. Is gcmanager-1.so in any postgres volume?
find /var/lib/docker/volumes -name 'gcmanager-1.so' 2>/dev/null
```

If any of these return results → you have this infection.

---

## Step 1 — Find All Infected Volumes

```bash
# Find the malicious library
find /var/lib/docker/volumes -name 'gcmanager-1.so' 2>/dev/null

# Find postgresql.conf files referencing it
find /var/lib/docker/volumes -name 'postgresql.conf' 2>/dev/null | \
    xargs grep -l 'gcmanager\|var/tmp\|/tmp/' 2>/dev/null
```

For each infected volume, note the volume name and the line number of the bad `shared_preload_libraries`.

---

## Step 2 — Identify the Container(s)

```bash
# Which container uses each infected volume?
docker ps --format '{{.ID}} {{.Names}}' | while read id name; do
    docker inspect $id --format "{{range .Mounts}}{{.Name}} {{end}}" | \
        grep -q '<volume_name>' && echo "Container: $name"
done
```

---

## Step 3 — Remove Persistence (do this BEFORE killing processes)

```bash
PG_DATA="/var/lib/docker/volumes/<volume_name>/_data"

# Remove the malicious .so
rm -f $PG_DATA/gcmanager-1.so

# Fix postgresql.conf (find the line number first)
grep -n shared_preload_libraries $PG_DATA/postgresql.conf
# Then fix that line (replace N with actual line number):
sed -i "Ns/.*/shared_preload_libraries = ''\\t# cleaned/" $PG_DATA/postgresql.conf

# Verify fix
grep -n shared_preload_libraries $PG_DATA/postgresql.conf
```

---

## Step 4 — Kill Active Malware Processes

```bash
# Kill all processes with exe in hidden /var/tmp dirs
for pid in $(ls /proc/ | grep '^[0-9]$\|^[0-9][0-9]*$'); do
    exe=$(readlink /proc/$pid/exe 2>/dev/null)
    [[ "$exe" == *"/var/tmp/."* || "$exe" == *"/tmp/."* ]] && \
        kill -9 $pid 2>/dev/null && echo "Killed PID $pid: $exe"
done
```

---

## Step 5 — Recreate the Container

```bash
cd /home/<user>/<project>

# Standard project name
docker compose stop db && docker compose rm -f db && docker compose up -d db

# If two projects share the same compose project name, use explicit -p:
docker stop <container_name> && docker rm <container_name>
docker compose -p <original_project_name> up -d db
```

---

## Step 6 — Verify Clean

```bash
# Wait 30 seconds for potential respawn
sleep 30

# Check for any miner processes
ls /proc/*/exe 2>/dev/null | while read f; do
    t=$(readlink $f 2>/dev/null)
    echo "$t" | grep -qE '/var/tmp/\.|/tmp/\.' && echo "STILL RUNNING: $t"
done || echo "CLEAN"

# Check volume is clean
find /var/lib/docker/volumes -name 'gcmanager-1.so' 2>/dev/null || echo "No gcmanager found - clean"

# CPU normalizing?
ps aux --sort=-%cpu | head -5
```

---

## Block Attacker IPs

```bash
iptables -A OUTPUT -d 185.132.53.73 -j DROP   # known miner pool
iptables -A OUTPUT -d 144.172.116.48 -j DROP   # known exfil C2
iptables-save > /etc/iptables/rules.v4
```

---

## Why `docker rm` + `docker run` Doesn't Fix This

The malware lives in the **Docker volume** (persistent), not in the **container layer** (ephemeral).

```
Container layer  ← wiped on docker rm   ← clean postgres image
     ↓ mounts
Volume data dir  ← NOT wiped            ← gcmanager-1.so lives here
  postgresql.conf (modified)
  gcmanager-1.so (malware)
```

Fix the volume first, then recreate the container.

---

## Notes

- The `.so` file is ~566KB. Any unexpected `.so` file in a postgres data directory is a red flag.
- Miners use randomized binary names and directory names every spawn — don't rely on filename matching.
- Always use `/proc/<PID>/exe` to find the real binary, not the process display name.
- Kernel threads (`[kworker/...]`) have zero RSS in legitimate cases — any such process with RAM is malware.
