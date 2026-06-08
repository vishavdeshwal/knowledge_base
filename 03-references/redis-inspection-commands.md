# Redis Inspection Commands — Field Reference
> Use this when you need to inspect a Redis instance and determine what it's doing,
> how healthy it is, or debug a specific concern.

---

## 1. Connect to Redis

```bash
# Without auth
redis-cli -h <endpoint> -p 6379

# With auth token
redis-cli -h <endpoint> -p 6379 -a <auth-token>

# AWS ElastiCache (no auth, inside VPC via bastion or ECS exec)
redis-cli -h <elasticache-endpoint> -p 6379
```

---

## 2. First Things First — What Is This Redis Being Used For?

```bash
# How many keys, which DBs are active, expiry stats
INFO keyspace

# Sample keys — look at naming pattern
SCAN 0 COUNT 100

# Total key count
DBSIZE
```

**Read the key names:**
| Pattern | What it is |
|---------|-----------|
| `rq:job:*`, `rq:results:*`, `rq:worker:*` | RQ job queue (Python) |
| `bull:*` | Bull job queue (Node.js) |
| `celery-task-meta-*` | Celery job queue (Python) |
| `session:*` | Session store |
| `user:123`, `order:456`, `product:*` | Application cache |
| Random UUIDs as key names | Job queue |
| Meaningful IDs as key names | Cache |

---

## 3. Check Key Types and TTLs

```bash
# What data type is a key
TYPE <key>

# How long until it expires
# Returns: positive = seconds left, -1 = no expiry, -2 = key doesn't exist
TTL <key>

# Same as TTL but in milliseconds
PTTL <key>

# Look inside a key based on its type
GET <key>           # string
HGETALL <key>       # hash (shows all fields)
LRANGE <key> 0 -1   # list (shows all items)
SMEMBERS <key>      # set
ZRANGE <key> 0 -1 WITHSCORES  # sorted set
```

---

## 4. Check for Keys Without Expiry

```bash
# Shows total keys, keys with expiry, and average TTL
INFO keyspace
```

**Output:**
```
db0:keys=3941,expires=2030,avg_ttl=25002520623
```

**Calculate:**
```
Keys without expiry = keys - expires
                    = 3941 - 2030 = 1911

% without expiry    = 1911 / 3941 × 100 = 48%

Average TTL in days = avg_ttl ÷ 1000 ÷ 86400
                    = 25002520623 ÷ 1000 ÷ 86400 = 289 days
```

**Thresholds:**
| % without expiry | Verdict |
|-----------------|---------|
| 0–10% | Healthy |
| 10–30% | Investigate |
| 30%+ | Concern — keys accumulating |

---

## 5. Check Cache Health (Hit Rate)

```bash
# Get hit/miss counts since server started
INFO stats
```

Look for:
```
keyspace_hits:8523
keyspace_misses:148221
```

**Calculate hit rate:**
```
hit rate = keyspace_hits / (keyspace_hits + keyspace_misses) × 100
         = 8523 / (8523 + 148221) × 100 = 5.4%
```

**Thresholds:**
| Hit rate | Verdict |
|----------|---------|
| 80%+ | Healthy cache |
| 40–80% | Underperforming — investigate TTLs or key mismatch |
| 5–30% | Broken cache or mixed use |
| ~0–5% | Not a cache — likely a job queue |

```bash
# Reset stats counters if you want a fresh measurement
CONFIG RESETSTAT
# Then wait a few minutes and run INFO stats again
```

---

## 6. Check Job Queue Health (RQ Specific)

```bash
# How many jobs are waiting to be picked up
LLEN rq:queue:default
LLEN rq:queue:high
LLEN rq:queue:low

# How many jobs in each state
# (RQ stores these in sorted sets)
ZCARD rq:finished:default     # completed jobs
ZCARD rq:failed:default       # failed jobs
ZCARD rq:scheduled:default    # scheduled future jobs
ZCARD rq:started:default      # currently running

# Look inside a specific job
HGETALL rq:job:<uuid>
# Shows: func_name, args, status, enqueued_at, ended_at, exc_info (if failed)

# List active workers
SMEMBERS rq:workers

# Check a specific worker
HGETALL rq:worker:<worker-id>
```

**What to look for:**
| Concern | Command | Red flag |
|---------|---------|----------|
| Jobs piling up | `LLEN rq:queue:default` | Growing number over time |
| Failed jobs | `ZCARD rq:failed:default` | Non-zero and increasing |
| No workers running | `SMEMBERS rq:workers` | Empty set |
| Orphaned job keys | `INFO keyspace` expires vs keys | >30% without expiry |

---

## 7. Check Memory

```bash
# Full memory report
INFO memory
```

Key fields to look at:
```
used_memory_human       # memory Redis is actually using
used_memory_peak_human  # highest memory ever used
maxmemory               # configured limit (0 = no limit)
maxmemory_policy        # what happens when memory is full
mem_fragmentation_ratio # healthy = 1.0–1.5, >2.0 = fragmentation concern
```

```bash
# How many keys were evicted (kicked out due to memory pressure)
INFO stats | grep evicted_keys

# How many keys expired naturally
INFO stats | grep expired_keys
```

**Eviction policies:**
| Policy | Behaviour |
|--------|-----------|
| `noeviction` | Returns error when full — dangerous for prod |
| `allkeys-lru` | Evicts least recently used keys |
| `volatile-lru` | Only evicts keys that have a TTL set |
| `volatile-ttl` | Evicts keys with shortest TTL first |

---

## 8. Check What Commands Are Being Run Most

```bash
INFO commandstats
```

**What dominant commands tell you:**
| Heavy commands | What Redis is being used for |
|---------------|------------------------------|
| `GET` + `SET` | Cache |
| `LPUSH` + `BRPOP` | Job queue |
| `ZADD` + `ZRANGE` | Scheduled jobs or leaderboard |
| `HGET` + `HSET` | Structured object store |
| `XADD` + `XREAD` | Event stream |

---

## 9. Check Connections

```bash
INFO clients
```

Key fields:
```
connected_clients       # current open connections
blocked_clients         # clients waiting on BRPOP/BLPOP (normal for job queues)
rejected_connections    # connections refused — means maxclients hit
```

```bash
# See all connected clients
CLIENT LIST
```

---

## 10. Check Slow Queries

```bash
# Show last 10 slow queries (>10ms by default)
SLOWLOG GET 10

# How many slow queries recorded total
SLOWLOG LEN

# Reset slow log
SLOWLOG RESET
```

---

## 11. Quick Full Health Check — Run All at Once

Paste this block when you first connect to any Redis and want a full picture:

```bash
INFO keyspace
INFO memory
INFO stats
INFO clients
INFO replication
DBSIZE
SLOWLOG LEN
```

Then based on what you see in keyspace, either follow Section 5 (cache) or Section 6 (job queue).

---

## 12. Scan for Keys Matching a Pattern

```bash
# Never use KEYS * in production — it blocks Redis
# Always use SCAN instead

# All keys
SCAN 0 COUNT 100

# Keys matching a pattern
SCAN 0 MATCH rq:job:* COUNT 100

# Keep scanning (use the cursor from previous result until cursor = 0)
SCAN <cursor> MATCH rq:job:* COUNT 100
```

---

## 13. Check Replication (Primary/Replica)

```bash
INFO replication
```

Key fields:
```
role                    # master or slave
connected_slaves        # how many replicas connected
master_link_status      # up = replica is in sync
master_last_io_seconds  # seconds since last sync (should be low)
replication_lag         # bytes replica is behind
```

---

## Reference — TTL Return Values

| TTL returns | Meaning |
|-------------|---------|
| Positive number | Seconds until key expires |
| `-1` | Key exists but has NO expiry |
| `-2` | Key does not exist |
