# Database Administration Guide

### Complete Reference: Fundamentals to Advanced

*From Users & Databases to Replication, Binlogs & Incident Response*

---

# Chapter 1: The Big Picture — How a Database Server Works

Before diving into commands, you need to understand how a database server is structured. Think of it like a building with multiple layers of security and organization.

## 1.1 The Three Layers of a Database

| Layer             | What It Is                                                | Real World Analogy                   |
| ----------------- | --------------------------------------------------------- | ------------------------------------ |
| Server / Instance | The running database process (MariaDB, MySQL, PostgreSQL) | The entire office building           |
| Database (Schema) | A named collection of tables inside the server            | One floor/department in the building |
| Table             | Rows and columns of actual data                           | Filing cabinets with files           |
| User              | An identity that can connect and perform actions          | An employee with a keycard           |

---

## 1.2 Users, Authentication & Authorization

This is the most fundamental concept. Every connection to a database must be:

* **Authenticated** — prove who you are (username + password)
* **Authorized** — prove you are allowed to do what you want (privileges/grants)

### How MySQL/MariaDB Identifies a User

In MySQL/MariaDB, a user is identified by TWO things: username AND the host they connect from:

```sql
-- User Identity Format:
'username'@'host'

'erpadmin'@'%'           -- % means from ANY IP
'erpadmin'@'10.0.2.163'  -- only from this specific IP
'erpadmin'@'localhost'   -- only from same machine
```

> 💡 **This is why you got `Access denied for erpadmin@10.0.2.163`** — the user exists but the host combination didn't match or the password was wrong.

---

### Privilege Levels (Authorization)

| Privilege Level      | Example                           | What It Controls                |
| -------------------- | --------------------------------- | ------------------------------- |
| Global (`*.*`)     | `GRANT ALL ON *.*`              | Everything on the entire server |
| Database (`db.*`)  | `GRANT ALL ON tenxyou.*`        | Everything in one database      |
| Table (`db.table`) | `GRANT SELECT ON tenxyou.users` | One specific table              |
| Column level         | `GRANT SELECT (name) ON ...`    | One specific column             |

---

### Common Privileges Explained

| Privilege                   | What It Allows              | Who Needs It         |
| --------------------------- | --------------------------- | -------------------- |
| `SELECT`                  | Read data                   | App users, reporting |
| `INSERT`                  | Add new rows                | App users            |
| `UPDATE`                  | Modify rows                 | App users            |
| `DELETE`                  | Remove rows                 | App users            |
| `CREATE`                  | Create tables/databases     | Developers, DBAs     |
| `DROP`                    | Delete tables/databases     | DBAs only            |
| `SUPER`                   | Everything — bypass limits | Master user only     |
| `REPLICATION SLAVE`       | Read binary logs            | Replica servers      |
| `REPLICATION SLAVE ADMIN` | Start/stop replication      | DBAs                 |
| `SLAVE MONITOR`           | Run `SHOW SLAVE STATUS`   | DBAs, monitoring     |
| `BINLOG MONITOR`          | Read binary log events      | DBAs                 |

```sql
-- Check privileges
SHOW GRANTS FOR CURRENT_USER;
SHOW GRANTS FOR 'erpadmin'@'%';
SELECT * FROM information_schema.USER_PRIVILEGES WHERE GRANTEE LIKE '%erpadmin%';

-- Grant privileges
GRANT SELECT, INSERT ON tenxyou.* TO 'erpadmin'@'%';
GRANT REPLICATION SLAVE ADMIN ON *.* TO 'erpadmin'@'%';
FLUSH PRIVILEGES;  -- apply changes
```

---

# Chapter 2: Binary Logs (Binlogs) — The Database's Activity Journal

Binary logs are one of the most important and least understood concepts in database administration. They are the foundation of replication, point-in-time recovery, and auditing.

## 2.1 What Is a Binary Log?

A binary log is a file that records every change made to the database — every INSERT, UPDATE, DELETE, CREATE, DROP. Think of it as a detailed journal or ledger of all database changes.

| Aspect          | Detail                                                                    |
| --------------- | ------------------------------------------------------------------------- |
| Format          | Binary (not human readable directly) — needs `mysqlbinlog`tool to read |
| Contents        | Every data change: INSERT, UPDATE, DELETE, DDL (CREATE/ALTER/DROP)        |
| Does NOT log    | SELECT queries (reads don't change data)                                  |
| File naming     | `mysql-bin-changelog.000001`,`.000002`, etc. (increments)             |
| Location on RDS | Managed by AWS, accessible via `SHOW BINLOG EVENTS`                     |
| Rotation        | New file created when size limit reached or server restarts               |

---

## 2.2 Why Do Binlogs Exist?

* **Replication** — Replica reads primary's binlog and replays changes
* **Point-in-time Recovery** — Restore DB to exact moment before disaster
* **Auditing** — See exactly what changed, when, and from which connection
* **Debugging** — Trace what caused data corruption or unexpected changes

---

## 2.3 Binlog Retention — Why Your Logs Were Gone

> ⚠️ **Your Incident:** Your binlog retention was `NULL` — meaning AWS RDS deleted binlogs immediately after they were no longer needed for replication. When replication broke, those binlogs were already gone — making the deletion completely untraceable.

```sql
-- Check current retention
CALL mysql.rds_show_configuration;

-- Set retention to 7 days (recommended)
CALL mysql.rds_set_configuration('binlog retention hours', 168);
```

| Retention Setting | Meaning                                            | Recommended For                    |
| ----------------- | -------------------------------------------------- | ---------------------------------- |
| `NULL`          | Delete immediately after replication consumes them | Never recommended                  |
| `24`            | Keep for 1 day                                     | Low storage, low risk environments |
| `72`            | Keep for 3 days                                    | Minimum for production             |
| `168`           | Keep for 7 days                                    | Recommended for production ✅      |
| `720`           | Keep for 30 days                                   | Compliance/audit requirements      |

---

## 2.4 Reading Binlogs — Finding Who Did What

```sql
-- List available binlog files
SHOW BINARY LOGS;

-- Read events from a specific binlog
SHOW BINLOG EVENTS IN 'mysql-bin-changelog.081747' FROM 497903500 LIMIT 50;
```

```bash
# Read binlog from command line (most detail)
mysqlbinlog \
  --read-from-remote-server \
  --host=your-db-host \
  --user=admin --password \
  --start-position=497903500 \
  --stop-position=497903700 \
  mysql-bin-changelog.081747
```

The binlog output tells you:

* Exact timestamp of every change
* Thread ID (connection that made the change)
* Which user and host ran the query
* The exact SQL that was executed

---

# Chapter 3: Replication — How Primary & Replica Stay in Sync

Replication is the process of automatically copying data changes from one database server (primary) to another (replica). This is what your `erp-prod-db → erp-prod-read-replica` setup uses.

## 3.1 How Replication Works — Step by Step

| Step | What Happens                                                         | Component      |
| ---- | -------------------------------------------------------------------- | -------------- |
| 1    | App writes data to Primary (INSERT/UPDATE/DELETE)                    | Primary DB     |
| 2    | Primary records the change in its Binary Log                         | Primary Binlog |
| 3    | Replica's**IO Thread**connects to Primary and reads the binlog | IO Thread      |
| 4    | IO Thread writes the events to Replica's**Relay Log**          | Relay Log      |
| 5    | Replica's**SQL Thread**reads the Relay Log and applies changes | SQL Thread     |
| 6    | Data is now identical on both Primary and Replica                    | Replica DB     |

---

## 3.2 The Two Replication Threads — Most Important Concept

Understanding these two threads is KEY to diagnosing any replication issue:

| Thread               | Job                                                          | If Stopped Means                                     |
| -------------------- | ------------------------------------------------------------ | ---------------------------------------------------- |
| **IO Thread**  | Connects to primary and downloads binlog events to relay log | Can't receive data from primary (network/auth issue) |
| **SQL Thread** | Reads relay log and applies changes to replica database      | Receiving data but can't apply it (conflict/error)   |

> ⚠️ **Your Case:** IO Thread was running (`Yes`) but SQL Thread was stopped (`No`). The replica was receiving data fine but couldn't apply a DELETE because the row didn't exist on the replica.

---

## 3.3 Replication Lag — What the Numbers Mean

| Seconds_Behind_Master | Meaning                                       | Action Needed             |
| --------------------- | --------------------------------------------- | ------------------------- |
| `0`                 | Fully in sync — perfect!                     | None                      |
| `1–60`             | Slight lag — normal under load               | Monitor                   |
| `60–300`           | Moderate lag — investigate                   | Check SQL thread, storage |
| `300+`              | Serious lag — replica falling behind         | Urgent investigation      |
| `NULL`              | Replication completely stopped                | Immediate fix needed      |
| `-1`                | RDS cannot calculate lag (replication broken) | Immediate fix needed      |

---

## 3.4 Checking Replication Status

```sql
-- The most important replication command
SHOW SLAVE STATUS\G
```

Key fields to check every time:

| Field                     | What to Look For                   | Problem If                       |
| ------------------------- | ---------------------------------- | -------------------------------- |
| `Slave_IO_Running`      | `Yes`                            | `No`= can't connect to primary |
| `Slave_SQL_Running`     | `Yes`                            | `No`= error applying changes   |
| `Seconds_Behind_Master` | `0`or small number               | `NULL`or `-1`= broken        |
| `Last_IO_Error`         | Empty                              | Any text = network/auth error    |
| `Last_SQL_Error`        | Empty                              | Any text = data conflict error   |
| `Master_Log_File`       | Should match primary's current log | Gap = binlog purged              |
| `Relay_Log_Space`       | Should not grow indefinitely       | Growing = SQL thread stuck       |

---

## 3.5 Common Replication Errors and Fixes

| Error Code | Error Name                | Cause                                              | Fix                               |
| ---------- | ------------------------- | -------------------------------------------------- | --------------------------------- |
| `1032`   | `HA_ERR_KEY_NOT_FOUND`  | DELETE/UPDATE on row that doesn't exist on replica | Skip event or resync replica      |
| `1062`   | `ER_DUP_ENTRY`          | INSERT of row that already exists on replica       | Skip event or resync replica      |
| `1045`   | `ER_ACCESS_DENIED`      | Wrong credentials for replication user             | Fix replication user password     |
| `1236`   | `ER_MASTER_FATAL_ERROR` | Binlog position lost or purged                     | Resync replica from scratch       |
| `1146`   | `ER_NO_SUCH_TABLE`      | Table exists on primary but not replica            | Create table on replica or resync |

---

## 3.6 Fixing Replication — Your Exact Scenario

Error `1032` means replica tried to DELETE a row that didn't exist. The safe fix:

```sql
-- Step 1: Stop the slave
STOP SLAVE;

-- Step 2: Skip the bad event
SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1;

-- Step 3: Restart replication
START SLAVE;

-- Step 4: Verify it's working
SHOW SLAVE STATUS\G
```

> ⚠️ **What Skipping Means:** Skipping an event means that specific change is ignored on the replica. If it was a DELETE of an error log row, the replica keeps that row. This creates a minor inconsistency but replication continues.

```bash
# If errors keep repeating — resync from scratch

# Delete broken replica
aws rds delete-db-instance \
  --db-instance-identifier erp-prod-read-replica \
  --skip-final-snapshot

# Create fresh replica from primary
aws rds create-db-instance-read-replica \
  --db-instance-identifier erp-prod-read-replica \
  --source-db-instance-identifier erp-prod-db \
  --availability-zone ap-south-1b
```

---

# Chapter 4: Database Logs — Your Eyes Inside the Database

Logs are how you see what is happening inside a database. Different logs serve different purposes. Understanding which log to look at saves hours of debugging.

## 4.1 Types of Database Logs

| Log Type       | What It Records                                        | Performance Impact | Enable in Prod?              |
| -------------- | ------------------------------------------------------ | ------------------ | ---------------------------- |
| Error Log      | DB errors, crashes, replication issues, startup events | Zero               | Always ✅                    |
| Slow Query Log | Queries exceeding time threshold (e.g. >2 seconds)     | Minimal (~0.1%)    | Yes ✅                       |
| Audit Log      | WHO did WHAT — user, IP, operation, timestamp         | Low (~1–3%)       | Yes ✅                       |
| General Log    | Every single query, every connection                   | High (10–15%)     | Only for debugging ⚠️      |
| Binary Log     | All data changes for replication and recovery          | Low (~1%)          | Always (enables replication) |
| Relay Log      | Binlog events received from primary (replica only)     | Minimal            | Auto-managed                 |
| InnoDB Log     | Transaction logs for crash recovery                    | Minimal            | Always (automatic)           |

---

## 4.2 Audit Log vs General Log — Key Difference

| Feature             | Audit Log                             | General Log                   |
| ------------------- | ------------------------------------- | ----------------------------- |
| Purpose             | Security & compliance — WHO did WHAT | Debugging — WHAT queries ran |
| Records user info   | Yes — username, IP, timestamp        | Partial — thread ID only     |
| Records all queries | Configurable (DML only recommended)   | Every single query            |
| Storage usage       | Moderate                              | Massive — GBs per day        |
| Performance impact  | Low 1–3%                             | High 10–15%                  |
| Best for            | Finding who deleted/changed data      | Debugging query issues        |
| Production safe     | Yes ✅                                | Only temporarily ⚠️         |

---

## 4.3 Enabling Logs on AWS RDS

```
RDS Console → Your DB → Modify
→ Additional configuration → Log exports
  ☑ Audit log
  ☑ Error log
  ☑ Slow query log
→ Apply Immediately
```

```sql
-- Enable slow query log with threshold
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;   -- log queries > 2 seconds
SET GLOBAL log_queries_not_using_indexes = 'ON';
```

---

## 4.4 Reading Logs in CloudWatch

```bash
# Search logs via AWS CLI
aws logs filter-log-events \
  --log-group-name '/aws/rds/instance/erp-prod-db/audit' \
  --filter-pattern 'DELETE' \
  --region ap-south-1
```

---

# Chapter 5: Storage, Connections & Performance Basics

## 5.1 Storage and Why It Affects Replication

Storage is one of the most overlooked causes of database issues. When storage fills up, databases behave unpredictably:

| Storage % Used | What Happens                                                   |
| -------------- | -------------------------------------------------------------- |
| 0–70%         | Normal operation                                               |
| 70–85%        | Monitor closely, plan expansion                                |
| 85–95%        | Warning zone — slow queries, log writes may fail              |
| 95–100%       | Critical — replication stops, transactions fail, DB may crash |

```sql
-- Check storage inside DB
SELECT
  table_schema AS 'Database',
  SUM(data_length + index_length) / 1024 / 1024 AS 'Size (MB)'
FROM information_schema.tables
GROUP BY table_schema
ORDER BY 2 DESC;
```

```
-- Check free storage via CloudWatch:
CloudWatch → Metrics → RDS → FreeStorageSpace
Set alarm: Alert when FreeStorageSpace < 20% of total
```

---

## 5.2 Connections

Every application that connects to the database uses one connection slot. Too many connections = database refuses new ones.

```sql
-- Check current connections
SHOW STATUS LIKE 'Threads_connected';
SHOW PROCESSLIST;   -- see what each connection is doing

-- Check max allowed connections
SHOW VARIABLES LIKE 'max_connections';

-- Kill a stuck/long-running query
SHOW PROCESSLIST;           -- note the Id of stuck query
KILL QUERY <process_id>;    -- kill just the query
KILL <process_id>;          -- kill the entire connection
```

---

## 5.3 Key Performance Metrics to Monitor

| Metric              | Where to Check            | Alert Threshold          |
| ------------------- | ------------------------- | ------------------------ |
| CPU Utilization     | RDS Console → Monitoring | > 80% sustained          |
| FreeStorageSpace    | CloudWatch Metrics        | < 20% of total           |
| DatabaseConnections | CloudWatch Metrics        | > 80% of max_connections |
| ReplicaLag          | CloudWatch Metrics        | > 300 seconds            |
| ReadLatency         | CloudWatch Metrics        | > 20ms                   |
| WriteLatency        | CloudWatch Metrics        | > 20ms                   |
| DiskQueueDepth      | CloudWatch Metrics        | > 10                     |

---

# Chapter 6: Incident Response Playbook

## 6.1 Replication Broken / -1 Lag Playbook

| Step               | Command                                     | What to Look For                                |
| ------------------ | ------------------------------------------- | ----------------------------------------------- |
| 1. Check status    | `SHOW SLAVE STATUS\G`                     | Slave_IO_Running, Slave_SQL_Running, Last_Error |
| 2. Identify thread | Look at IO vs SQL Running                   | Which thread stopped tells you the problem type |
| 3. Read error      | `Last_SQL_Error`or `Last_IO_Error`field | Error code (1032, 1062, 1236, etc.)             |
| 4. Check storage   | CloudWatch FreeStorageSpace metric          | Ensure not full                                 |
| 5. Fix error       | `STOP SLAVE; SKIP; START SLAVE;`          | Slave_SQL_Running becomes Yes                   |
| 6. Monitor lag     | Watch Seconds_Behind_Master                 | Should decrease toward 0                        |

---

## 6.2 Access Denied Troubleshooting Playbook

| Step | Action                                                                           |
| ---- | -------------------------------------------------------------------------------- |
| 1    | Note the full error:`Access denied for 'user'@'host'`                          |
| 2    | Check if user exists:`SELECT user, host FROM mysql.user WHERE user='erpadmin'` |
| 3    | Check their grants:`SHOW GRANTS FOR 'erpadmin'@'%'`                            |
| 4    | Try connecting from different host or with different credentials                 |
| 5    | Check `site_config.json`or `.env`files for app credentials                   |
| 6    | Check AWS Secrets Manager for stored credentials                                 |
| 7    | If all fails: Reset password from RDS Console → Modify → Master password       |

---

## 6.3 Slow Database Playbook

```sql
-- Find slowest running queries right now
SHOW PROCESSLIST;
-- Look for queries with Time > 10 seconds

-- Find queries without indexes (causing full table scans)
SELECT * FROM information_schema.TABLE_STATISTICS
ORDER BY rows_read DESC LIMIT 10;

-- Find largest tables consuming storage
SELECT table_name,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
WHERE table_schema = 'tenxyou'
ORDER BY size_mb DESC LIMIT 20;
```

---

# Chapter 7: RDS-Specific Operations on AWS

## 7.1 What RDS Manages For You

| Task              | On-Premise DBA Does         | On RDS                               |
| ----------------- | --------------------------- | ------------------------------------ |
| Backups           | Manual scripts, cron jobs   | Automatic daily snapshots            |
| Patching          | Manual OS + DB updates      | AWS handles (maintenance window)     |
| Failover          | Manual promotion of replica | Automatic with Multi-AZ              |
| Storage scaling   | Manual disk expansion       | Can enable auto-scaling              |
| Replication setup | Complex manual config       | One-click read replica creation      |
| SUPER privilege   | Available to root           | Not available — use RDS equivalents |

---

## 7.2 RDS Special Stored Procedures

Since SUPER privilege is not available on RDS, AWS provides special stored procedures:

| Procedure                                                      | What It Does                          | Equivalent to                       |
| -------------------------------------------------------------- | ------------------------------------- | ----------------------------------- |
| `mysql.rds_show_configuration`                               | Show RDS-specific settings            | Custom RDS command                  |
| `mysql.rds_set_configuration('binlog retention hours', 168)` | Set binlog retention                  | SUPER privilege command             |
| `mysql.rds_stop_replication`                                 | Stop replication safely               | STOP SLAVE                          |
| `mysql.rds_start_replication`                                | Start replication                     | START SLAVE                         |
| `mysql.rds_skip_repl_error`                                  | Skip replication error                | SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1 |
| `mysql.rds_set_external_master`                              | Configure external replication source | CHANGE MASTER TO                    |

---

## 7.3 RDS Parameter Groups

Parameter groups are how you configure database settings on RDS — equivalent to editing `my.cnf` on a regular server.

```
-- Common parameters to tune:
innodb_buffer_pool_size    -- Memory for caching (set to 70% of RAM)
max_connections            -- Maximum simultaneous connections
slow_query_log             -- Enable slow query logging (1 = on)
long_query_time            -- Threshold for slow query log (seconds)
general_log                -- Enable general log (0 = off in prod)
binlog_format              -- ROW recommended for replication
```

---

# Chapter 8: Prevention & Best Practices

## 8.1 The DBA Golden Rules

* **Never write directly to a read replica** — it should always be `read_only=ON`
* **Never share the master user credentials** — create separate users per application
* **Always set binlog retention** — minimum 72 hours, ideally 7 days
* **Enable audit logs from day one** — you can't investigate what you didn't log
* **Set up CloudWatch alarms** — don't wait to discover problems manually
* **Test your backups** — a backup you've never restored is not a backup
* **Always modify primary, never replica** — password changes, schema changes go to primary

---

## 8.2 CloudWatch Alarms to Set Up Right Now

| Alarm                | Metric              | Threshold        | Why                            |
| -------------------- | ------------------- | ---------------- | ------------------------------ |
| Replication Lag      | ReplicaLag          | > 300 seconds    | Catch replication issues early |
| Low Storage          | FreeStorageSpace    | < 20% of total   | Prevent storage-caused outages |
| High CPU             | CPUUtilization      | > 80% for 10 min | Catch performance issues       |
| Too Many Connections | DatabaseConnections | > 80% of max     | Prevent connection exhaustion  |
| Read Latency         | ReadLatency         | > 0.02 seconds   | Detect slow reads              |

---

## 8.3 Weekly DBA Health Checks

```sql
-- 1. Check replication status
SHOW SLAVE STATUS\G

-- 2. Check storage usage per database
SELECT table_schema, SUM(data_length+index_length)/1024/1024 AS mb
FROM information_schema.tables GROUP BY table_schema ORDER BY mb DESC;

-- 3. Check for long running queries
SELECT * FROM information_schema.processlist WHERE time > 60;

-- 4. Check binlog retention
CALL mysql.rds_show_configuration;

-- 5. Verify read_only on replica
SHOW VARIABLES LIKE 'read_only';  -- must be ON
```

---

## 8.4 Lessons From Today's Incident

| Problem Faced                            | Root Cause                                           | Prevention                                        |
| ---------------------------------------- | ---------------------------------------------------- | ------------------------------------------------- |
| -1 Replication Lag                       | SQL Thread stopped due to Error 1032 (missing row)   | Enable audit logs + monitor replica lag           |
| Couldn't trace deletion                  | Binlog retention was NULL — logs purged immediately | Set binlog retention to 168 hours                 |
| No CloudWatch DB logs                    | Log exports not configured on RDS                    | Enable Error + Audit + Slow Query logs at setup   |
| erpadmin missing REPLICATION SLAVE ADMIN | User created without full replication privileges     | Create DBA user with proper privileges from start |
| Couldn't connect to primary              | Different password on primary vs replica             | Store credentials in AWS Secrets Manager          |

---

# Quick Reference Card — Commands You'll Use Most

## Replication

```sql
SHOW SLAVE STATUS\G                          -- Check replication health
STOP SLAVE;                                  -- Stop replication
START SLAVE;                                 -- Start replication
SET GLOBAL SQL_SLAVE_SKIP_COUNTER = 1;       -- Skip one bad event
SHOW BINARY LOGS;                            -- List binlog files
SHOW BINLOG EVENTS IN 'file' FROM pos;       -- Read binlog events
```

## Users & Privileges

```sql
SHOW GRANTS FOR CURRENT_USER;                -- My privileges
SHOW GRANTS FOR 'user'@'%';                  -- Another user's privileges
GRANT privilege ON db.* TO 'user'@'%';       -- Grant privilege
REVOKE privilege ON db.* FROM 'user'@'%';    -- Remove privilege
CREATE USER 'newuser'@'%' IDENTIFIED BY 'pass'; -- Create user
DROP USER 'user'@'%';                        -- Delete user
```

## Databases & Tables

```sql
SHOW DATABASES;                              -- List all databases
USE tenxyou;                                 -- Switch to database
SHOW TABLES;                                 -- List tables
DESCRIBE tablename;                          -- Show table structure
SHOW CREATE TABLE tablename\G               -- Full table definition
```

## Performance & Monitoring

```sql
SHOW PROCESSLIST;                            -- Active connections/queries
KILL QUERY <id>;                             -- Kill a query
SHOW STATUS LIKE 'Threads_connected';        -- Connection count
SHOW VARIABLES LIKE 'max_connections';       -- Max connections
SHOW VARIABLES LIKE 'read_only';             -- Is replica read-only?
```

## RDS Specific

```sql
CALL mysql.rds_show_configuration;
CALL mysql.rds_set_configuration('binlog retention hours', 168);
CALL mysql.rds_skip_repl_error;
```

---

> 💡 **Final Tip:** Save this document and keep it handy. Every command here was relevant to a real incident. The more you practice reading `SHOW SLAVE STATUS\G` and `SHOW PROCESSLIST`, the faster you will diagnose issues.
>
