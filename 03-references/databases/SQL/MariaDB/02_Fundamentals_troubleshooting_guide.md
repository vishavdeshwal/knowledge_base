# MariaDB Fundamentals — Knowledge Base
> Built from real-world debugging: 32s → 2s query fix on Gynoveda Pre-Prod  
> Author: Vishav Deshwal | Infinite Locus Private Limited

---

## Table of Contents

1. [What is a Database?](#1-what-is-a-database)
2. [How MariaDB Finds Data](#2-how-mariadb-finds-data)
3. [Indexes — The Shortcut Structure](#3-indexes--the-shortcut-structure)
4. [JOINs — Combining Tables](#4-joins--combining-tables)
5. [The InnoDB Buffer Pool — MariaDB's RAM Cache](#5-the-innodb-buffer-pool--mariadbs-ram-cache)
6. [How Everything Connects](#6-how-everything-connects)
7. [The Real Incident — 32 Seconds to 2 Seconds](#7-the-real-incident--32-seconds-to-2-seconds)
8. [Diagnostic Framework](#8-diagnostic-framework)
9. [MariaDB Tuning Reference](#9-mariadb-tuning-reference)
10. [Quick Command Reference](#10-quick-command-reference)

---

## 1. What is a Database?

A database is a collection of **tables**. Each table is exactly like an Excel spreadsheet — rows and columns.

```
tabItem table:
┌─────────────┬──────────────────────┬───────────┬──────────┐
│ item_code   │ item_name            │ item_group│ disabled │
├─────────────┼──────────────────────┼───────────┼──────────┤
│ SILVER-3M   │ 3M Silver Couple     │ Products  │ 0        │
│ GOLD-6M     │ 6M Gold Single       │ Products  │ 0        │
│ CONSULT-1ST │ 1st Consult          │ Services  │ 0        │
│ AYUR-12M    │ 12M Ayurveda Pack    │ Products  │ 0        │
│ HERB-3M     │ 3M Herbal Single     │ Products  │ 1        │ ← disabled
└─────────────┴──────────────────────┴───────────┴──────────┘
```

Data is stored across **multiple tables** to avoid repetition. Item names live in `tabItem`. Prices live in `tabItem Price`. Stock levels live in `tabBin`. They are linked by a shared column — `item_code`.

---

## 2. How MariaDB Finds Data

When you run a query like:

```sql
SELECT * FROM tabItem WHERE item_code = 'GOLD-6M';
```

MariaDB has to **find** that row. It has two strategies.

---

### Strategy 1 — Full Table Scan (No Index)

MariaDB checks every single row from top to bottom:

```
tabItem has 10,000 rows

Checking row 1:    SILVER-3M   → not it, skip
Checking row 2:    CONSULT-1ST → not it, skip
Checking row 3:    GOLD-6M     → FOUND ✅
Checking row 4:    AYUR-12M    → still checking (already found but doesn't stop)
...
Checking row 9999: HERB-3M     → still checking
Checking row 10000: ...        → done

Total rows checked: 10,000
```

This is called a **Full Table Scan**. It works but it is extremely slow on large tables. MariaDB has no way to "know" where GOLD-6M is without reading every row.

This is like finding a contact in a phone with no search feature — you scroll through every single name.

---

### Strategy 2 — Index Lookup (With Index)

An index gives MariaDB a **sorted shortcut list** it can jump into directly:

```
Index on item_code (sorted alphabetically):

AYUR-12M    → points to row 4
CONSULT-1ST → points to row 2
GOLD-6M     → points to row 3  ← jump directly here
HERB-3M     → points to row 5
SILVER-3M   → points to row 1

Total rows checked: 1 (using binary search on the sorted index)
```

This is like a book's index at the back. Instead of reading every page, you look up the term and jump to the exact page number.

**Speed difference:**

```
Table with 1,000,000 rows:

Full Table Scan  → checks 1,000,000 rows → ~5 seconds
Index Lookup     → checks ~20 rows (binary search) → ~0.001 seconds
```

---

## 3. Indexes — The Shortcut Structure

### What an Index Actually Is

An index is a **separate sorted data structure** stored on disk alongside your table. It is NOT a copy of the table. It only contains the indexed column(s) and pointers (row locations).

```
Your database files:

/var/lib/mysql/your_database/
├── tabItem.ibd          ← actual table data (unsorted rows)
├── tabItem.idx          ← index (sorted shortcuts + row pointers)
├── tabItem_Price.ibd
├── tabItem_Price.idx
└── tabBin.ibd
```

The index is automatically maintained by MariaDB — every time you INSERT, UPDATE, or DELETE a row, MariaDB updates both the table and the index.

---

### How to Create an Index

You create indexes manually. MariaDB does not auto-index everything.

```sql
-- Basic index on a single column
CREATE INDEX idx_item_group ON tabItem (item_group);

-- Composite index on multiple columns (order matters)
CREATE INDEX idx_item_price ON `tabItem Price` (item_code, price_list);

-- Unique index (also enforces uniqueness)
CREATE UNIQUE INDEX unique_item_warehouse ON tabBin (item_code, warehouse);
```

After creation, MariaDB uses the index automatically for relevant queries. You don't do anything extra.

Frappe/ERPNext creates indexes automatically during `bench migrate` for commonly queried fields. This is why `SHOW INDEX FROM tabItem` already showed indexes — Frappe built them during setup.

---

### The Trade-Off — Reads vs Writes

| Operation | Without Index | With Index |
|---|---|---|
| SELECT (read) | Slow — scans all rows | Fast — uses shortcut |
| INSERT (write) | Fast — just add row | Slightly slower — updates table AND index |
| UPDATE (write) | Fast | Slightly slower |
| DELETE (write) | Fast | Slightly slower |
| Disk space | Less | More (index stored separately) |

**Rule:** Only index columns you frequently search, filter, or JOIN on. Don't index everything.

---

### When MariaDB IGNORES Your Index

This is critical. Having an index doesn't guarantee it will be used.

**Case 1 — Low cardinality (too few unique values)**
```sql
-- disabled column has only 2 values: 0 or 1
-- 9,999 out of 10,000 rows have disabled = 0
-- Index is USELESS here — faster to scan all rows

SELECT * FROM tabItem WHERE disabled = 0;
-- MariaDB ignores the disabled index, does full scan instead
```

MariaDB decides: "If I'm going to return 99% of the table anyway, why bother with the index?"

**Case 2 — Function wrapping the column**
```sql
-- Index on item_code EXISTS but this BREAKS it:
SELECT * FROM tabItem WHERE UPPER(item_code) = 'GOLD-6M';
--                          ↑ function applied = index skipped

-- Fix: store data consistently and query without functions
SELECT * FROM tabItem WHERE item_code = 'GOLD-6M';
```

**Case 3 — LIKE with a leading wildcard**
```sql
-- This USES the index ✅ (starts with known prefix)
WHERE item_code LIKE 'GOLD%'

-- This IGNORES the index ❌ (could match anywhere in string)
WHERE item_code LIKE '%GOLD%'
--                    ↑ leading wildcard = index useless = full scan
```

**Case 4 — OR condition spanning multiple columns**
```sql
-- This ignores indexes on both columns
WHERE item_code = 'GOLD-6M' OR item_group = 'Products'
-- MariaDB falls back to full scan
```

---

### How to Check If a Query Uses an Index — EXPLAIN

`EXPLAIN` is your most powerful diagnostic tool. It shows MariaDB's query execution plan before running the query.

```sql
EXPLAIN SELECT * FROM tabItem WHERE item_group = 'Products';
```

Output:
```
+------+------+-------------+------+---------------+------------+------+-------+
| type | key  | key_len     | ref  | rows          | Extra      |      |       |
+------+------+-------------+------+---------------+------------+------+-------+
| ref  | item_group | 768   | const| 63            | Using where|      |       |
+------+------+-------------+------+---------------+------------+------+-------+
```

**What each column means:**

| Column | What it tells you |
|---|---|
| `type` | How the table is accessed (most important) |
| `key` | Which index is being used (`NULL` = no index) |
| `rows` | Estimated rows MariaDB will scan |
| `Extra` | Additional info about the operation |

**The `type` column — from best to worst:**

```
system  → Only 1 row in table. Best possible.
const   → Single row lookup (WHERE id = 5). Excellent.
eq_ref  → One row per JOIN. Very good.
ref     → Index used, multiple rows possible. Good.
range   → Index used for a range (BETWEEN, >, <). Acceptable.
index   → Full index scan (better than ALL but still slow). Mediocre.
ALL     → Full table scan. No index used. WORST. Fix immediately.
```

**Rule: If you see `type = ALL` on a large table, you have a problem.**

---

## 4. JOINs — Combining Tables

### Why Data is Split Across Tables

Storing everything in one table causes problems:

```
BAD — Everything in one table:
┌─────────────┬──────────┬────────┬──────────────┐
│ item_code   │ price    │ stock  │ warehouse    │
├─────────────┼──────────┼────────┼──────────────┤
│ SILVER-3M   │ 22000    │ 10     │ Malad Bin    │
│ SILVER-3M   │ 22000    │ 5      │ Thane Bin    │  ← price duplicated
│ SILVER-3M   │ 22000    │ 3      │ Viman Bin    │  ← price duplicated again
│ GOLD-6M     │ 45000    │ 8      │ Malad Bin    │
└─────────────┴──────────┴────────┴──────────────┘

Problem: If price changes, you update hundreds of rows
```

```
GOOD — Split into separate tables:

tabItem Price:              tabBin:
┌──────────┬───────┐       ┌──────────┬──────────┬───────┐
│item_code │ price │       │item_code │warehouse │ stock │
├──────────┼───────┤       ├──────────┼──────────┼───────┤
│SILVER-3M │ 22000 │       │SILVER-3M │ Malad    │ 10    │
│GOLD-6M   │ 45000 │       │SILVER-3M │ Thane    │ 5     │
└──────────┴───────┘       │GOLD-6M   │ Malad    │ 8     │
                            └──────────┴──────────┴───────┘

Price stored once. Change it once, everywhere updated.
```

A JOIN is how you **combine these tables back together** at query time.

---

### How a JOIN Works

```sql
SELECT
  item.item_name,
  price.price_list_rate,
  bin.actual_qty
FROM tabItem item
LEFT JOIN `tabItem Price` price
  ON price.item_code = item.item_code       ← match on this shared column
  AND price.price_list = 'Standard Selling'
LEFT JOIN tabBin bin
  ON bin.item_code = item.item_code         ← match on this shared column
  AND bin.warehouse = 'Malad Bin'
WHERE item.disabled = 0;
```

MariaDB executes this step by step internally:

```
Step 1: Get all active items from tabItem
        item_code: [SILVER-3M, GOLD-6M, CONSULT-1ST ...]
        (uses disabled index)

Step 2: For EACH item, find its price in tabItem Price
        SILVER-3M → 22000  (uses item_code index on tabItem Price)
        GOLD-6M   → 45000
        CONSULT   → 2000

Step 3: For EACH item, find stock in tabBin
        SILVER-3M → 10 units  (uses item_code index on tabBin)
        GOLD-6M   → 8 units
        CONSULT   → NULL (service, no stock)

Step 4: Combine into final result
        ┌──────────────┬────────┬───────┐
        │ item_name    │ price  │ stock │
        ├──────────────┼────────┼───────┤
        │ 3M Silver    │ 22000  │ 10    │
        │ 6M Gold      │ 45000  │ 8     │
        │ 1st Consult  │ 2000   │ NULL  │
        └──────────────┴────────┴───────┘

Step 5: Return to Python/Frappe as one combined result
```

**Critical point:** Your backend code (Python/Frappe) sends ONE SQL query. MariaDB handles all the steps above internally. Python only receives the final combined table — it never sees the intermediate steps.

```
Python/Frappe                         MariaDB
     │                                    │
     │── ONE SQL query ──────────────────►│
     │                                    │ Step 1: load tabItem pages
     │                                    │ Step 2: load tabItem Price pages
     │                                    │ Step 3: load tabBin pages
     │                                    │ Step 4: JOIN all three in memory
     │◄── final combined result ──────────│
     │                                    │
```

---

### Types of JOINs

```
tabItem:          tabItem Price:
A                 A → price 1
B                 C → price 2
C
D

INNER JOIN — only rows that exist in BOTH tables:
Result: A, C

LEFT JOIN — all rows from left table, matched data from right (NULL if no match):
Result: A (price 1), B (NULL), C (price 2), D (NULL)

RIGHT JOIN — all rows from right table, matched data from left:
Result: A (price 1), C (price 2)
```

Frappe uses `LEFT JOIN` almost everywhere because you want all items even if they don't have a price entry.

---

## 5. The InnoDB Buffer Pool — MariaDB's RAM Cache

### The Core Problem: Disk is Slow

```
Speed comparison:

RAM access:   ~100 nanoseconds    (0.0000001 seconds)
SSD access:   ~100 microseconds   (0.0001 seconds)    → 1,000x slower than RAM
HDD access:   ~10 milliseconds    (0.01 seconds)      → 100,000x slower than RAM
```

Every time MariaDB reads data from disk instead of RAM, it pays a massive performance penalty. The buffer pool exists to minimise disk reads.

---

### What the Buffer Pool Is

The buffer pool is MariaDB's RAM workspace. It caches database pages (chunks of table data) so that repeated queries don't hit the disk.

```
┌─────────────────────────────────────────────────────────┐
│                   InnoDB Buffer Pool                     │
│                    (RAM — fast)                          │
│                                                          │
│  ┌──────────────────┐   ┌───────────────────────────┐   │
│  │   Data Pages     │   │      Index Pages           │   │
│  │                  │   │                            │   │
│  │  tabItem rows    │   │  item_code index           │   │
│  │  tabBin rows     │   │  item_group index          │   │
│  │  tabItem Price   │   │  warehouse index           │   │
│  │  rows            │   │                            │   │
│  └──────────────────┘   └───────────────────────────┘   │
│                                                          │
│  ┌───────────────────────────────────────────────────┐   │
│  │           Adaptive Hash Index (AHI)               │   │
│  │                                                    │   │
│  │  MariaDB watches frequent queries and auto-builds  │   │
│  │  a hash table for instant lookups:                 │   │
│  │                                                    │   │
│  │  'SILVER-3M' ──────────────► page 4, offset 128   │   │
│  │  'GOLD-6M'   ──────────────► page 7, offset 32    │   │
│  │                                                    │   │
│  │  No config needed. Fully automatic.                │   │
│  └───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
           ▲
           │ fetched from disk only when not in pool
           │
┌─────────────────────────────────────────────────────────┐
│                   Disk (slow)                            │
│  tabItem.ibd  tabBin.ibd  tabItem_Price.ibd  ...         │
└─────────────────────────────────────────────────────────┘
```

---

### Pages — The Unit of Storage

MariaDB doesn't read individual rows from disk. It reads **pages** — fixed 16KB chunks that contain multiple rows.

```
tabItem on disk, split into 16KB pages:

Page 1 (16KB): items 1–50
Page 2 (16KB): items 51–100
Page 3 (16KB): items 101–150
...
Page 200 (16KB): items 9951–10000
```

When you query for GOLD-6M, MariaDB loads the entire page containing that row into the buffer pool — not just the single row. This is intentional: nearby rows are likely to be queried soon too (spatial locality).

---

### How the Buffer Pool Works in Practice

```
Query: SELECT * FROM tabItem WHERE item_code = 'GOLD-6M'

First run (cold cache):
1. MariaDB checks buffer pool → page not there
2. Reads page from disk → slow (disk I/O)
3. Loads page into buffer pool
4. Returns GOLD-6M row
Time: ~50ms

Second run (warm cache):
1. MariaDB checks buffer pool → page IS there
2. Returns GOLD-6M row directly from RAM
Time: ~0.1ms
```

This is why **first page load in a Frappe app is slow** but subsequent pages are fast — the buffer pool is warming up.

---

### Buffer Pool Size — Why It Matters

The buffer pool has a fixed size. When it's full and a new page needs to come in, MariaDB **evicts** the least recently used page (LRU algorithm).

```
Buffer Pool = 128MB (default — dangerously small)

Load tabItem pages      → 40MB used
Load tabItem Price pages → 30MB used → total 70MB
Load tabBin pages        → 80MB needed → POOL IS FULL ❌

MariaDB must evict tabItem pages to fit tabBin
Then next query needs tabItem → fetch from disk again
Then evict tabBin → fetch from disk for next tabBin query
→ Constantly reading from disk
→ Called "buffer pool thrashing"
→ 32 SECONDS
```

```
Buffer Pool = 4GB (tuned)

Load tabItem pages      → 40MB used
Load tabItem Price pages → 30MB used → total 70MB
Load tabBin pages        → 80MB used → total 150MB

All three tables fit comfortably in buffer pool ✅
JOIN happens entirely in RAM
→ 2 SECONDS
```

---

### The Adaptive Hash Index — Auto-Magic Caching

The AHI is MariaDB watching your queries and optimising itself:

```
MariaDB notices this query runs 500 times/hour:
SELECT * FROM tabItem WHERE item_code = 'SILVER-3M'

Normally: binary search through B-tree index → ~10 steps

AHI kicks in automatically:
Builds a hash map: 'SILVER-3M' → exact page + offset
Now: direct hash lookup → 1 step

No configuration needed. MariaDB does this automatically.
```

Think of it like this: a regular index is a sorted phone book (you still flip through it). AHI is a direct contact card — you go straight to the person without flipping at all.

---

### Buffer Pool vs Redis — Key Differences

Both are caches. Understanding the difference matters.

| | InnoDB Buffer Pool | Redis (Frappe) |
|---|---|---|
| **What it caches** | Raw database pages (rows + indexes) | API responses, session data, doctypes |
| **Who manages it** | MariaDB automatically | You explicitly set/get keys |
| **Awareness** | Knows nothing about your app | Knows exactly what you cache |
| **Eviction** | LRU (least recently used) | Configurable (LRU, LFU, etc.) |
| **On restart** | Cache is lost — cold start | Can persist to disk |
| **Layer** | DB level (inside MariaDB) | App level (between app and DB) |

Frappe uses **both simultaneously**:

```
Browser request
      │
      ▼
Frappe checks Redis cache
      │
      ├── Cache HIT  → return immediately (no DB query)
      │
      └── Cache MISS → run SQL query
                              │
                              ▼
                        MariaDB checks Buffer Pool
                              │
                              ├── Buffer HIT  → return from RAM
                              │
                              └── Buffer MISS → read from disk
```

Redis saves you from hitting the DB at all. Buffer pool saves you from hitting the disk. Both reduce latency at different layers.

---

## 6. How Everything Connects

Here is the complete picture from a browser request to a database row:

```
Browser: "Show me POS items"
      │
      ▼
nginx (reverse proxy)
      │
      ▼
Gunicorn (Python WSGI server)
      │
      ▼
Frappe framework
      │
      ├─► Check Redis cache
      │         │
      │    HIT ─┘ → return cached response immediately
      │    MISS → continue
      │
      ▼
Python executes get_items()
      │
      ▼
Frappe builds SQL query (JOIN on 3 tables)
      │
      ▼
MariaDB receives query
      │
      ├─► Use INDEX to identify relevant rows quickly
      │
      ├─► Load pages into BUFFER POOL (from disk if not cached)
      │
      ├─► Execute JOIN in buffer pool (all in RAM)
      │
      └─► Return combined result
              │
              ▼
Python receives result
      │
      ▼
Frappe serialises to JSON
      │
      ▼
Browser renders POS items
```

Performance can break at any layer:
- **nginx** — misconfiguration, proxy timeouts
- **Gunicorn** — too few workers, OOM kills
- **Redis** — cache miss rate too high
- **SQL query** — no indexes, bad query structure
- **Buffer pool** — too small, constant disk reads
- **Disk** — slow I/O, overloaded storage

---

## 7. The Real Incident — 32 Seconds to 2 Seconds

### The Setup

| | Prod | Pre-Prod |
|---|---|---|
| Database | AWS RDS (managed) | Local MariaDB (default config) |
| `get_items` API | 878ms | 32,000ms |
| `innodb_buffer_pool_size` | ~8GB (auto-tuned by AWS) | 128MB (default) |

### The Query That Was Slow

The `get_items` API runs a JOIN across three tables:

```sql
SELECT
  item.item_code,
  item.item_name,
  item.image,
  price.price_list_rate,
  bin.actual_qty
FROM `tabItem` item
LEFT JOIN `tabItem Price` price
  ON price.item_code = item.item_code
  AND price.price_list = 'Standard Selling'
LEFT JOIN `tabBin` bin
  ON bin.item_code = item.item_code
  AND bin.warehouse = '1004 Warehouse'
WHERE item.disabled = 0
  AND item.item_group = 'All Item Groups'
LIMIT 40;
```

### Why It Was 32 Seconds

```
Buffer Pool = 128MB

Step 1: Load tabItem pages into buffer pool
        tabItem = ~40MB → buffer pool at 40MB / 128MB

Step 2: Load tabItem Price pages
        tabItem Price = ~30MB → buffer pool at 70MB / 128MB

Step 3: Load tabBin pages
        tabBin = ~80MB → FULL at 128MB ❌
        
        To fit tabBin, evict tabItem pages back to disk
        
Step 4: JOIN needs tabItem again
        tabItem pages are gone → read from disk again
        tabBin gets evicted → read from disk again
        ...
        
Repeated disk I/O = 32 seconds
```

### The Diagnostic Steps

```
1. Ruled out application (same Frappe code on both servers)

2. Ruled out network (internal curl test same result)

3. Compared infrastructure
   Prod  = RDS (managed, tuned)
   Preprod = Local MariaDB → suspected tuning issue

4. Checked indexes
   SHOW INDEX FROM tabBin          → indexes present ✅
   SHOW INDEX FROM tabItem Price   → indexes present ✅
   SHOW INDEX FROM tabItem         → indexes present ✅
   → Not an index problem

5. Checked buffer pool
   SHOW VARIABLES LIKE 'innodb_buffer_pool_size'
   → 134217728 (128MB) ← ROOT CAUSE FOUND

6. Fixed
   innodb_buffer_pool_size = 4G
   sudo systemctl restart mariadb

7. Result
   32 seconds → under 2 seconds ✅
```

### The Fix

```bash
# Edit MariaDB config
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf

# Add under [mysqld]:
innodb_buffer_pool_size = 4G
innodb_buffer_pool_instances = 4
query_cache_size = 256M
query_cache_type = 1

# Restart
sudo systemctl restart mariadb
```

---

## 8. Diagnostic Framework

Use this framework whenever you encounter a slow query or API.

### Step 1 — Isolate the Layer

```
API is slow
      │
      ├─► Is it slow every time or just first run?
      │         First run only = cold buffer pool (normal, not a bug)
      │         Every run = structural issue
      │
      ├─► Is it slow from outside the server?
      │   Test from inside: curl http://127.0.0.1:8000/api/...
      │         Same slowness = not a network/nginx issue
      │         Fast inside = nginx or network problem
      │
      └─► Is it a specific query or all queries?
                Specific query = index or query structure issue
                All queries = buffer pool, disk I/O, or connection issue
```

### Step 2 — Check Buffer Pool Hit Rate

```sql
SELECT
  (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100
  AS buffer_hit_rate_pct
FROM (
  SELECT VARIABLE_VALUE AS Innodb_buffer_pool_reads
  FROM information_schema.GLOBAL_STATUS
  WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads'
) reads,
(
  SELECT VARIABLE_VALUE AS Innodb_buffer_pool_read_requests
  FROM information_schema.GLOBAL_STATUS
  WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'
) requests;
```

| Hit Rate | Meaning | Action |
|---|---|---|
| > 99% | Healthy | Buffer pool is fine |
| 95–99% | Marginal | Consider increasing buffer pool |
| < 95% | Problem | Buffer pool too small — increase immediately |
| < 70% | Critical | Severe disk thrashing — increase urgently |

### Step 3 — Find the Slow Query

```sql
-- Enable slow query log
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 2;  -- log queries taking > 2 seconds
SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';

-- Then reproduce the slow operation
-- Then check the log:
-- sudo tail -50 /var/log/mysql/slow.log
```

### Step 4 — Diagnose the Slow Query

```sql
-- Run EXPLAIN on the slow query
EXPLAIN SELECT item.item_name, price.price_list_rate
FROM tabItem item
JOIN `tabItem Price` price ON price.item_code = item.item_code
WHERE item.disabled = 0;
```

Look for:
- `type = ALL` → full table scan → needs an index
- `key = NULL` → no index used → create one
- `rows` very high → scanning too many rows

### Step 5 — Check Running Queries

```sql
-- See what MariaDB is currently doing
SHOW FULL PROCESSLIST;

-- Look for:
-- Time > 5 = query running for 5+ seconds (bad)
-- State = 'Copying to tmp table' = complex query without good indexes
-- State = 'Waiting for table lock' = locking issue
```

### Step 6 — Check InnoDB Engine Status

```sql
SHOW ENGINE INNODB STATUS\G

-- Look for in the output:
-- Buffer pool hit rate (should be 999/1000 or better)
-- Pending reads (should be 0 or near 0)
-- LOG section for write bottlenecks
```

---

## 9. MariaDB Tuning Reference

### Buffer Pool Sizing Rule

```
innodb_buffer_pool_size = 50-70% of total RAM

Server RAM    →  Buffer Pool Size
4GB           →  2GB
8GB           →  4-5GB
12GB          →  6-8GB    ← Gynoveda pre-prod (set to 4GB, can go to 6GB)
16GB          →  10GB
32GB          →  20GB
64GB          →  40GB
```

### Recommended Config for a 12GB ERPNext Server

```ini
# /etc/mysql/mariadb.conf.d/50-server.cnf
[mysqld]

# ── Buffer Pool ──────────────────────────────────────────
innodb_buffer_pool_size = 6G
innodb_buffer_pool_instances = 6    # 1 instance per 1GB

# ── Log Files ────────────────────────────────────────────
innodb_log_file_size = 512M         # larger = fewer checkpoints = faster writes
innodb_log_buffer_size = 64M

# ── Query Cache ──────────────────────────────────────────
query_cache_type = 1                # enable query cache
query_cache_size = 256M             # cache up to 256MB of query results
query_cache_limit = 8M              # max size of individual cached query

# ── Connections ──────────────────────────────────────────
max_connections = 200
thread_cache_size = 16

# ── I/O Optimisation ─────────────────────────────────────
innodb_flush_method = O_DIRECT      # skip OS cache, write directly to disk
innodb_io_capacity = 400            # tune to your disk's IOPS

# ── Slow Query Logging (always keep ON) ──────────────────
slow_query_log = ON
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2                 # log queries slower than 2 seconds
log_queries_not_using_indexes = ON  # also log queries skipping indexes
```

---

## 10. Quick Command Reference

### Check Buffer Pool Status
```sql
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';
```

### Check Indexes on a Table
```sql
SHOW INDEX FROM `tabItem`;
SHOW INDEX FROM `tabBin`;
SHOW INDEX FROM `tabItem Price`;
```

### Diagnose a Slow Query
```sql
EXPLAIN SELECT ... your query here ...;
```

### Check Running Queries
```sql
SHOW FULL PROCESSLIST;
```

### Enable Slow Query Log (live)
```sql
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 2;
```

### Check MariaDB Version and Config
```bash
mysql --version
mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb%';"
```

### Restart MariaDB After Config Change
```bash
sudo systemctl restart mariadb
sudo systemctl status mariadb
```

### Connect to a Frappe Site DB
```bash
bench --site <sitename> mariadb
```

---

## Mental Model — One Diagram to Remember

```
Your Query (SELECT with JOIN)
           │
           ▼
    ┌─────────────┐
    │   INDEX     │  ← Sorted shortcut — finds the right rows fast
    │             │    without scanning every row
    └──────┬──────┘
           │ "these pages contain the rows you need"
           ▼
    ┌─────────────────────────────────┐
    │       BUFFER POOL (RAM)         │
    │                                 │
    │  tabItem pages    ✅ cached      │
    │  tabItem Price    ✅ cached      │  ← JOIN happens here
    │  tabBin pages     ✅ cached      │    entirely in RAM
    │                                 │    = FAST
    └─────────────────────────────────┘
           │
           │ if page NOT in buffer pool:
           ▼
    ┌─────────────┐
    │    DISK     │  ← 1000x slower than RAM
    │  (storage)  │    = buffer pool too small = YOUR 32 SECOND PROBLEM
    └─────────────┘


Fix:
  innodb_buffer_pool_size too small
  → all three tables can't fit simultaneously
  → constant disk reads during JOIN
  → 32 seconds

  innodb_buffer_pool_size = 4GB
  → all three tables fit in RAM
  → JOIN happens entirely in buffer pool
  → 2 seconds
```

---