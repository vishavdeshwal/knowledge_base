# Database Fundamentals — From Query Lifecycle to the Full Landscape

> Built from a real production debugging session on Gynoveda's MariaDB. Everything here was learned by tracing an actual 11am slowness incident from first principles.

---

## Table of Contents

1. [The Full Query Lifecycle](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#1-the-full-query-lifecycle)
2. [MariaDB Thread Pool — What Happens When a Query Arrives](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#2-mariadb-thread-pool)
3. [MVCC (Multi-Version Concurrency Control) — How Databases Handle Concurrent Reads and Writes](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#3-mvcc-multi-version-concurrency-control)
4. [The Diagnostic Stack — How to Debug DB Slowness](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#4-the-diagnostic-stack)
5. [Key Variables and Status Counters](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#5-key-variables-and-status-counters)
6. [The Database Landscape — Every Type Explained](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#6-the-database-landscape)
7. [OLTP vs OLAP — The Most Important Distinction](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#7-oltp-vs-olap)
8. [What to Read Next](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#8-what-to-read-next)
9. [Personal Runbook — Debug Any DB Slowness in 2 Minutes](https://claude.ai/chat/70197c55-e91e-4812-b742-87c65e0bb420#9-personal-runbook)

---

## 1. The Full Query Lifecycle

When your application makes a database query, this is the complete path:

```
Application (pod / EC2)
  │
  ├─ ORM / Query Builder       → generates SQL from code
  ├─ Connection Pool           → waits for a free connection slot
  └─ TCP Socket                → already open, sends SQL bytes
          │
          ▼
      Network (VPC)
          │  TCP packet traversal + latency (negligible inside VPC)
          ▼
      MariaDB Server
          │
          ├─ Thread Pool       → assign worker thread (cached or new)
          ├─ Auth Check        → only on first connection, not every query
          ├─ Parser            → is this valid SQL? build syntax tree
          ├─ Optimizer         → what's the cheapest execution plan?
          ├─ Lock Acquisition  → write? acquire row lock. read? MVCC snapshot
          │
          └─ InnoDB Storage Engine
               ├─ Buffer Pool Check  → is this data page in RAM?
               │    hit  → read from memory (~microseconds)
               │    miss → load 16KB page from disk (~milliseconds)
               └─ Row fetch, filter, sort, limit
          │
          ▼
      Result rows sent back over TCP
          │
          ▼
      ORM Deserialization      → rows → Python/Go/JS objects
          │
          ▼
      Response to user
```

### Key insight: where time actually goes

| Stage                   | Typical cost                    | What makes it slow                    |
| ----------------------- | ------------------------------- | ------------------------------------- |
| Connection pool wait    | 0ms → seconds                  | Pool exhausted — no free slots       |
| Thread spawn            | 1–5ms                          | Cache miss, new OS thread needed      |
| Parser + Optimizer      | <1ms simple, up to 10ms complex | Missing indexes, bad statistics       |
| Lock acquisition        | 0ms → minutes                  | Row/table lock contention             |
| Buffer pool hit         | ~microseconds                   | Normal                                |
| Buffer pool miss (disk) | ~milliseconds                   | Buffer pool too small                 |
| Row fetch + sort        | depends                         | Full scan, no index, large result set |
| ORM deserialization     | depends                         | Fetching 10K rows you didn't need     |

---

## 2. MariaDB Thread Pool

### Per-connection model (default)

Every connection from your app pool gets its own OS thread. When a query arrives:

```
TCP packet on port 3306
        │
        ▼
Thread cache lookup
        │
   ┌────┴────┐
   │         │
cached     new thread
thread     spawned
~μs        ~1-5ms
   │         │
   └────┬────┘
        │
        ▼
State: "starting"
Read query bytes, auth check (if new connection), select DB
        │
        ▼
Parser → Optimizer
Lex, parse, rewrite, cost-based plan selection
        │
        ▼
Lock acquisition
Write → exclusive row lock
Read  → no lock (MVCC snapshot) ← most common path
        │
        ▼
InnoDB execution
buffer pool read → row fetch → MVCC version check
        │
        ▼
Result sent to client
Thread → Sleep state, parked in cache
```

### SHOW PROCESSLIST states decoded

| State                    | Meaning                           | Action                            |
| ------------------------ | --------------------------------- | --------------------------------- |
| `starting`             | Reading query bytes               | Normal                            |
| `Opening tables`       | Acquiring metadata lock           | Watch if slow                     |
| `Waiting for lock`     | InnoDB lock contention            | 🔴 Investigate                    |
| `Sending data`         | Reading and sending rows          | Normal if brief                   |
| `Sorting result`       | Filesort — no index for ORDER BY | Optimize query                    |
| `Copying to tmp table` | GROUP BY without index, spilling  | Optimize query                    |
| `Sleep`                | Idle, waiting for next query      | Normal <60s, investigate if hours |

### Thread cache variables

```sql
SHOW VARIABLES LIKE 'thread_cache_size';
SHOW STATUS LIKE 'Threads_created';    -- keeps climbing = cache too small
SHOW STATUS LIKE 'Threads_cached';     -- parked threads right now
SHOW STATUS LIKE 'Threads_connected';  -- total open connections
SHOW STATUS LIKE 'Threads_running';    -- actually executing right now
```

**Critical ratio:** `Threads_running / Threads_connected`

* `connected=20, running=1` → DB is idle, bottleneck is upstream (pool exhaustion)
* `connected=20, running=20` → DB is genuinely saturated

---

## 3. MVCC (Multi-Version Concurrency Control)

### The problem it solves

Without MVCC, every `SELECT` would have to wait for concurrent `UPDATE`s to finish. Reads block on writes. This kills throughput.

MVCC's answer: **readers never wait for writers. They read an older version of the data.**

### How it works

Every row in InnoDB carries a hidden **transaction ID** — the ID of the last transaction that wrote it. When you update a row, InnoDB:

1. Writes the new version to the data page
2. Pushes the old version into the **undo log**
3. Links them in a version chain (newest → older → oldest)

When a transaction starts a `SELECT`, InnoDB records a **snapshot** — essentially noting: *"this transaction can only see rows whose transaction ID was committed before this moment."*

When reading a row, InnoDB checks: *is this version visible to my snapshot?*

* Yes → return it
* No → walk the undo log chain backwards until finding a visible version

### Example

```
Timeline:  t=100          t=200              t=300 (now)
           Row created    Row updated        A is updating again
           balance=100    balance=300 ✓      balance=500 (uncommitted)

Transaction B starts at t=200 → snapshot = 200
Transaction B reads: sees balance=300 (committed before snapshot)
Transaction B ignores: balance=500 (txn 300 > snapshot 200, uncommitted)
No lock. No wait. Consistent read.
```

### What MVCC gives you

| Benefit             | In practice                                       |
| ------------------- | ------------------------------------------------- |
| Non-blocking reads  | `SELECT`never waits for a concurrent `UPDATE` |
| Consistent snapshot | You see DB state as of your transaction start     |
| No dirty reads      | Never see half-committed data                     |

### The hidden cost: undo log bloat

If a transaction starts and never commits (your sleeping connections with `Time: 8392`), InnoDB **cannot purge** old row versions — because that open transaction might still need them.

This causes:

* Undo log grows on disk
* Every read must walk longer version chains
* InnoDB slows down even though CPU and query count look normal

**Check for open transactions:**

```sql
SELECT trx_id, trx_started, trx_state, trx_mysql_thread_id,
       TIMESTAMPDIFF(SECOND, trx_started, NOW()) as age_seconds
FROM information_schema.innodb_trx
ORDER BY trx_started ASC;
```

If you see transactions started hours ago → undo log bloat is silently degrading performance.

---

## 4. The Diagnostic Stack

When your app is slow but DB metrics look normal, work through these layers top to bottom:

```
Layer 1: App / Connection Pool    → pool exhausted? ORM doing N+1?
Layer 2: Query                    → slow query log, EXPLAIN, bad patterns
Layer 3: Locks                    → lock waits, old open transactions
Layer 4: Memory                   → buffer pool hit rate, tmp table spills
Layer 5: I/O                      → disk reads, IOPS ceiling
Layer 6: Config                   → timeouts, connection limits
```

### "DB looks healthy" translation table

| Symptom                         | Looks normal in        | Actually broken at                                |
| ------------------------------- | ---------------------- | ------------------------------------------------- |
| App slow, DB idle               | CPU, query count, IOPS | **Connection pool**(app layer)              |
| Queries slow randomly           | CPU, IOPS              | **Lock waits**(lock layer)                  |
| Gradual slowdown over days      | CPU, connections       | **Undo log bloat**from open transactions    |
| Slow only for heavy queries     | Everything             | **Buffer pool too small**(memory layer)     |
| Sudden slowdown under load      | CPU                    | **Tmp tables spilling to disk**             |
| Timeouts occasionally           | Normal metrics         | **max_connections ceiling hit**             |
| Slowness at specific time daily | Everything             | **Analytics queries on OLTP DB**← Gynoveda |

---

## 5. Key Variables and Status Counters

### Query layer

```sql
SHOW VARIABLES LIKE 'slow_query_log';           -- should be ON
SHOW VARIABLES LIKE 'long_query_time';           -- set to 0.5 in prod
SHOW VARIABLES LIKE 'log_queries_not_using_indexes';
SHOW VARIABLES LIKE 'max_statement_time';        -- circuit breaker, kills runaway queries
SHOW STATUS LIKE 'Slow_queries';                 -- cumulative count
```

**Enable slow query log:**

```sql
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 0.5;
SET GLOBAL log_queries_not_using_indexes = ON;
```

### Lock layer

```sql
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';  -- default 50s
SHOW STATUS LIKE 'Innodb_row_lock_waits';        -- cumulative lock waits
SHOW STATUS LIKE 'Innodb_row_lock_time_avg';     -- avg wait in ms — if high, lock contention

-- Who is blocking whom right now
SELECT
  r.trx_mysql_thread_id AS waiting_thread,
  b.trx_mysql_thread_id AS blocking_thread,
  TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS wait_seconds
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx r ON w.requesting_trx_id = r.trx_id
JOIN information_schema.innodb_trx b ON w.blocking_trx_id = b.trx_id;
```

### Memory layer (buffer pool)

```sql
SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';  -- total page reads
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';           -- disk reads (misses)
SHOW STATUS LIKE 'Innodb_buffer_pool_wait_free';       -- pool too small

-- Hit rate formula (should be > 99%)
-- hit_rate = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)

SHOW STATUS LIKE 'Created_tmp_disk_tables';  -- should be 0
SHOW STATUS LIKE 'Created_tmp_tables';
```

### Connection layer

```sql
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'wait_timeout';              -- kill idle Sleep connections after N sec
SHOW VARIABLES LIKE 'thread_cache_size';
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Max_used_connections';         -- historical peak
SHOW STATUS LIKE 'Connection_errors%';           -- any refused connections?
```

### Performance schema — top queries by time

```sql
SELECT
  schema_name,
  LEFT(digest_text, 100) as query,
  count_star as exec_count,
  ROUND(avg_timer_wait/1000000000000, 3) as avg_sec,
  ROUND(max_timer_wait/1000000000000, 3) as max_sec,
  ROUND(sum_timer_wait/1000000000000, 3) as total_sec
FROM performance_schema.events_statements_summary_by_digest
WHERE schema_name = 'your_db'
ORDER BY avg_timer_wait DESC
LIMIT 20;
```

### Which users are burning the most time

```sql
SELECT
  user,
  ROUND(sum_timer_wait/1000000000000, 1) as total_sec,
  count_star as total_queries,
  ROUND(avg_timer_wait/1000000000000, 3) as avg_sec
FROM performance_schema.events_statements_summary_by_user_by_event_name
WHERE event_name = 'statement/sql/select'
ORDER BY sum_timer_wait DESC
LIMIT 10;
```

---

## 6. The Database Landscape

Every database type exists because someone hit a limitation of the previous one. The right question is always: **what problem does this type solve, and what does it trade away?**

---

### Relational (SQL)

**The bet:** Your data has structure. Relationships matter. Consistency is non-negotiable.

**Storage model:** Row-oriented. Each row stored together on disk. Great for fetching complete records.

**Query model:** SQL. Joins across tables. ACID transactions.

**Use when:** Financial systems, ERP, e-commerce, anything requiring joins and exact answers.

| Database        | Known for                                                                                               |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| PostgreSQL      | Most feature-rich open source SQL. JSON, extensions, window functions. Default choice for new products. |
| MySQL / MariaDB | Simpler, fast reads, massive ecosystem. Where most web apps live.                                       |
| SQLite          | Embedded, single file, serverless. Every mobile app and browser uses this.                              |
| Oracle          | Enterprise, expensive, dominant in banking/telco legacy.                                                |
| SQL Server      | Microsoft ecosystem. Common in .NET enterprises.                                                        |

---

### Document (NoSQL)

**The bet:** Your data doesn't have consistent shape. You want to store and retrieve whole objects without joins.

**Storage model:** JSON-like documents. Each document can have different fields.

**Trade-off:** Gain schema flexibility and horizontal scaling. Lose joins, cross-document transactions, enforced relationships.

**Use when:** Product catalogs (varied attributes per product), user profiles, CMS content, mobile app data.

**Real talk:** MongoDB was massively overhyped in 2010s. Many teams used it for everything and spent years migrating back to Postgres. Rule: if you're doing lots of filtering and aggregating *across* documents, you want SQL.

| Database  | Known for                                                             |
| --------- | --------------------------------------------------------------------- |
| MongoDB   | Most popular document DB. Flexible, good tooling, frequently misused. |
| CouchDB   | HTTP-native, excellent for offline-first sync.                        |
| Firestore | Google managed. Common in mobile apps.                                |

---

### Key-Value (NoSQL)

**The bet:** You don't need to query data — you just need to look it up by a known key. Speed above all else.

**Storage model:** Hash map. Key → Value. That's it.

**Trade-off:** Extreme speed. Zero query capability beyond exact key lookup.

**Use when:** Caching computed results, session storage, rate limiting counters, feature flags.

| Database  | Known for                                                                                    |
| --------- | -------------------------------------------------------------------------------------------- |
| Redis     | In-memory, sub-millisecond, supports lists/sets/sorted sets/streams. Your ERPNext uses this. |
| Memcached | Simpler than Redis, pure cache, nothing else.                                                |
| DynamoDB  | AWS managed, infinite scale, key-value + document hybrid.                                    |

---

### Wide-Column (NoSQL)

**The bet:** Massive write throughput. Billions of rows. You know your query patterns in advance and design around them.

**Storage model:** Tables where each row can have different columns. Data stored by column family on disk.

**Trade-off:** Extremely fast writes and reads  *by the right keys* . Nearly useless for ad-hoc queries. Schema design is hard — you design around queries, not entities.

**Use when:** IoT sensor data, metrics at scale, audit trails, anything append-heavy with billions of rows.

| Database  | Known for                                                           |
| --------- | ------------------------------------------------------------------- |
| Cassandra | Truly distributed, no single point of failure. Netflix/Apple scale. |
| ScyllaDB  | Cassandra-compatible, rewritten in C++, much faster.                |
| HBase     | Hadoop ecosystem.                                                   |
| Bigtable  | Google managed. What Cassandra was inspired by.                     |

---

### Time-Series

**The bet:** Your data is always timestamped, written in order, and queried by time ranges with aggregations.

**Storage model:** Columnar with specialized compression for sequential numeric data. Auto-downsampling and retention policies.

**Use when:** Infrastructure metrics (CPU/memory/latency), IoT sensor readings, financial tick data.

| Database        | Known for                                                                         |
| --------------- | --------------------------------------------------------------------------------- |
| Prometheus      | Pull-based metrics, PromQL. The standard for Kubernetes monitoring. You use this. |
| InfluxDB        | General time-series, push or pull.                                                |
| TimescaleDB     | PostgreSQL extension — SQL + time-series optimization.                           |
| VictoriaMetrics | Prometheus-compatible, more efficient at scale.                                   |
| ClickHouse      | Columnar OLAP, also excellent for time-series at scale.                           |

---

### Graph

**The bet:** Your most important queries are about *relationships* — not "give me this row" but "give me everything connected to this node within 3 hops."

**Storage model:** Nodes (entities) and edges (relationships). Queries traverse the graph.

**Use when:** Social networks (friends of friends), fraud detection (transaction patterns), recommendation engines, knowledge graphs.

| Database       | Known for                                    |
| -------------- | -------------------------------------------- |
| Neo4j          | Most mature graph DB. Cypher query language. |
| Amazon Neptune | AWS managed graph DB.                        |
| DGraph         | Distributed, GraphQL-native.                 |

---

### Search Engines

**The bet:** Users type words and you need relevant results fast — including typos, synonyms, and relevance ranking.

**Storage model:** Inverted index. Every word maps to which documents contain it.

**Use when:** Product search, log search, any search box experience.

| Database      | Known for                                              |
| ------------- | ------------------------------------------------------ |
| Elasticsearch | The standard. Also used for log analytics (ELK stack). |
| OpenSearch    | AWS fork of Elasticsearch.                             |
| Typesense     | Simpler, faster for pure search.                       |
| Meilisearch   | Developer-friendly, great defaults.                    |

---

### Columnar / OLAP

**The bet:** You query aggregations over massive datasets but only touch a few columns at a time.

**Storage model:** Column-oriented. Data for each column stored together. Reading `SUM(revenue)` over 100M rows touches only the revenue column.

**Trade-off:** Extremely fast for analytical aggregations. Poor for single-row lookups and frequent updates.

**Use when:** Data warehouses, BI dashboards, business reporting. **This is exactly where Gynoveda's dashboard queries belong** — those 45–180 second queries would run in under a second here.

| Database   | Known for                                                       |
| ---------- | --------------------------------------------------------------- |
| ClickHouse | Absurdly fast analytical queries. Best open-source OLAP.        |
| BigQuery   | Google managed, serverless, pay per query.                      |
| Redshift   | AWS managed data warehouse.                                     |
| Snowflake  | Cloud-native, separates storage and compute.                    |
| DuckDB     | Embedded OLAP — runs in-process like SQLite but for analytics. |

---

## 7. OLTP vs OLAP

This is the single most important distinction for understanding production database problems.

```
OLTP                                    OLAP
(Online Transaction Processing)         (Online Analytical Processing)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERPNext, Gynoveda app                   BI dashboards, reports
Many small queries, fast                Few large queries, slow by design
INSERT/UPDATE heavy                     SELECT-only, bulk reads
Milliseconds per query                  Seconds to minutes acceptable
Row-oriented storage (InnoDB)           Column-oriented (ClickHouse, Redshift)
Indexes on specific columns             Full scans expected and optimized
Many concurrent users                   Few analysts
Consistency critical                    Slightly stale data acceptable
```

### The Gynoveda incident in one sentence

> An OLAP workload (`prod_gynoveda_read` from `172.31.1.10`) was running analytical queries — CTEs, window functions, `COUNT(DISTINCTROW CASE WHEN...)` — against an OLTP database (MariaDB), exhausting the connection pool and polluting the buffer pool, causing app users to experience slowness at 11am every day.

### The fix hierarchy

```
Immediate  → SET GLOBAL max_statement_time = 30 (kill runaway queries faster)
This week  → Point BI tool at a dedicated read replica (isolate analytics traffic)
Proper fix → Move analytics to ClickHouse or DuckDB (right tool for the workload)
```

---

## 8. What to Read Next

### The one book that changes everything

**"Designing Data-Intensive Applications" — Martin Kleppmann**

The bible. Covers storage engines, replication, transactions, consistency models, distributed systems. Database-agnostic. Every senior SRE/Platform engineer has read this. Start here.

### For SQL internals and query optimization

**"Use The Index, Luke" — Markus Winand**

* Free at `use-the-index-luke.com`
* How indexes actually work inside the storage engine
* Written for developers, not DBAs
* Directly applicable to `EXPLAIN` output

### For MySQL/MariaDB specifically

**"High Performance MySQL" — Schwartz, Zaitsev, Tkachenko**

* The practitioner's reference
* Buffer pool tuning, replication, schema design, query optimization
* Use as reference, not cover to cover

### Videos

**CMU Database Group — Andy Pavlo (YouTube)**

* "Intro to Database Systems" and "Advanced Database Systems" — both free
* Grad-level content, teaches *why* InnoDB made the choices it made
* Covers storage engines, MVCC, concurrency control from scratch

**Hussein Nasser (YouTube)**

* Practical backend/database engineering
* 20–40 minute videos on connection pooling, indexing internals, tradeoffs

### The reading order

```
Right now     → use-the-index-luke.com (free, directly applicable)
Next month    → Designing Data-Intensive Applications (chapter by chapter)
Parallel      → CMU DB lectures on YouTube
After DDIA    → High Performance MySQL (reference)
```

### Don't skip this

Read the actual MariaDB Knowledge Base at `mariadb.com/kb` — not tutorials, the actual docs. The sections on InnoDB internals, transaction isolation levels, and the optimizer are written by the engineers who built it.

---

## 9. Personal Runbook — Debug Any DB Slowness in 2 Minutes

Run these in order. Stop at the first non-normal result — that's your layer.

```sql
-- Step 1: Is the DB actually doing anything?
SHOW STATUS LIKE 'Threads_running';
-- Normal: low number. If 0-1 while users complain → bottleneck is upstream.

-- Step 2: Active queries right now
SELECT id, user, host, db, command, time, state, info
FROM information_schema.processlist
WHERE command != 'Sleep'
ORDER BY time DESC;

-- Step 3: Any old open transactions?
SELECT trx_id, trx_started, trx_mysql_thread_id,
       TIMESTAMPDIFF(SECOND, trx_started, NOW()) as age_seconds
FROM information_schema.innodb_trx
ORDER BY trx_started ASC;
-- Anything > 60 seconds is suspicious. Hours = problem.

-- Step 4: Lock contention?
SHOW STATUS LIKE 'Innodb_row_lock%';
-- Innodb_row_lock_time_avg > 100ms = lock problem

-- Step 5: Buffer pool health?
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';
SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';
-- hit rate = 1 - (reads/read_requests). Below 99% = pool too small.

-- Step 6: Tmp table spills?
SHOW STATUS LIKE 'Created_tmp_disk_tables';
-- Should be 0. Any number here = queries spilling to disk.

-- Step 7: Connection ceiling?
SHOW STATUS LIKE 'Max_used_connections';
SHOW STATUS LIKE 'Connection_errors%';
-- Max_used_connections near max_connections = you've been hitting the ceiling.

-- Step 8: Who is running the heaviest queries?
SELECT
  user,
  ROUND(sum_timer_wait/1000000000000, 1) as total_sec,
  count_star as total_queries,
  ROUND(avg_timer_wait/1000000000000, 3) as avg_sec
FROM performance_schema.events_statements_summary_by_user_by_event_name
WHERE event_name = 'statement/sql/select'
ORDER BY sum_timer_wait DESC LIMIT 10;
```

### Before a known incident window (e.g. 10:55am)

```sql
-- Save baseline snapshot
SELECT 'BASELINE', NOW();
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Innodb_row_lock_waits';
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';
SHOW STATUS LIKE 'Created_tmp_disk_tables';
SHOW STATUS LIKE 'Slow_queries';
SHOW STATUS LIKE 'Max_used_connections';
```

Run the same block at 11:05 and 11:15. The **delta** tells you which layer is moving.

### After the incident — read the slow query log

```bash
# Summarize worst queries by total time
mysqldumpslow -s t -t 20 /var/log/mysql/slow-query.log

# On RDS: download from Console → Logs & events → slowquery/mysql-slowquery.log
```

---

## Appendix: The Gynoveda Incident Summary

**Symptom:** App slowness every day ~11am. DB metrics look normal.

**Investigation path:**

1. `SHOW PROCESSLIST` → 20 sleeping connections from `172.31.1.10`, idle for hours
2. `performance_schema.events_statements_summary_by_digest` → queries averaging 45–180 seconds, all hitting `max_statement_time` ceiling
3. `events_statements_summary_by_user_by_event_name` → `prod_gynoveda_read` user, avg 1.2s, 727 total queries
4. `172.31.1.10` identified as a BI/dashboard tool, not the ERP server

**Root cause:** Analytics/reporting queries (CTEs, window functions, `COUNT(DISTINCTROW CASE WHEN...)`) running against production OLTP database. Each dashboard load fired 10–20 queries taking 45–180 seconds, occupying the entire connection pool and polluting the InnoDB buffer pool with analytics pages.

**Fixes applied / recommended:**

* `SET GLOBAL max_statement_time = 30` (immediate — die faster, free connections sooner)
* Point BI tool at dedicated read replica (this week)
* Migrate analytics workload to ClickHouse or DuckDB (proper fix)

---

*Document built June 2026. Based on live debugging of Gynoveda production MariaDB on AWS RDS.*
