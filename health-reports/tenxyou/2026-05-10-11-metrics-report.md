# TenXYou Infrastructure Metrics Report
**Period:** 2026-05-10 00:00 UTC — 2026-05-11 23:59 UTC (48 hours)  
**Timezone Note:** All timestamps are UTC. India is UTC+5:30 (add 5h30m for IST)  
**Data Source:** AWS CloudWatch (1-hour aggregation periods)  
**Report Date:** 2026-05-12  

---

## ⚠️ Critical Note: Missing Metrics

**CloudWatch Agent is NOT installed on any EC2 instance.**  
This means the following metrics are **completely unavailable** from CloudWatch:

| Missing Metric | Why It's Missing | How to Get It |
|---|---|---|
| EC2 Memory Utilization | Requires CW Agent | Install `amazon-cloudwatch-agent`, add `mem_used_percent` |
| EC2 Disk Space / Inodes | Requires CW Agent | Add `disk_used_percent` for `/`, `/var`, `/data` |
| EC2 Swap Utilization | Requires CW Agent | Add `swap_used_percent` |
| Nginx request rates | Requires CW Agent + nginx log config | Add `access_log` metrics |
| PHP-FPM pool status | Requires CW Agent | Add PHP-FPM status plugin |

**Action Required:** Install CloudWatch Agent on all production EC2 instances. Without it, you are operationally blind to memory and disk on EC2.

---

## 1. EC2 CPU Utilization

> **What basic monitoring gives:** 5-minute sampling, aggregated to 1-hour here. Covers CPUUtilization only.

| Instance | 2-Day Avg CPU | Peak CPU | Peak Observed | Assessment |
|---|---|---|---|---|
| erp-prod (c5a.4xlarge) | 2.7% | 19.7% | — | ✅ Healthy, well under capacity |
| strapi-prod (t3a.2xlarge) | 1.9% | 16.5% | — | ✅ Healthy |
| strapi-preprod (t3a.2xlarge) | 0.2% | 3.7% | — | ✅ Idle |
| **wordpress-aboutus (t3.medium)** | **1.9%** | **99.5%** | **2026-05-12 00:00 UTC** | **🔴 CPU SPIKE — see below** |
| saleor-prod-dashboard (t3.medium) | 0.2% | 8.2% | — | ✅ Healthy |
| saleor-prod-worker-be (t3a.large) | 1.6% | 21.0% | — | ✅ Healthy |
| tenxyou-db-prod (t2.xlarge) | 1.1% | 5.9% | — | ✅ Low load |
| custom-db-read-replica (t2.xlarge) | 0.2% | 16.0% | — | ✅ Healthy |
| nginx-routing (t2.micro) | 0.3% | 20.0% | — | ✅ Healthy |
| ECS-Tenxyou-1 (t3.xlarge) | 6.9% | 30.1% | — | ✅ Normal |
| ECS-Tenxyou-2 (t3.xlarge) | 0.3% | 3.5% | — | ⚠️ Near-idle — imbalanced load |
| ECS-Tenxyou-3 (t3.xlarge) | 8.3% | 32.5% | — | ✅ Normal |
| ECS-Saleor-1 (t3.xlarge) | 2.9% | 36.8% | — | ✅ Normal |
| ECS-Saleor-2 (t3.xlarge) | 3.6% | 46.6% | — | ✅ Normal |
| ECS-Saleor-3 (t3.xlarge) | 0.3% | 3.5% | — | ⚠️ Near-idle — imbalanced load |
| ECS-Saleor-4 (t3.xlarge) | 1.6% | 21.4% | — | ✅ Normal |

### 1.1 WordPress CPU Spike — Root Cause Indicator

WordPress (`i-0fc2dc16732238cd6`) hit **99.5% CPU at 2026-05-12 00:00 UTC (05:30 IST today)**. This is the same instance that is currently failing its ALB health check. The spike aligns precisely with when the TG went unhealthy.

```
WordPress CPU Timeline (key hours):
  2026-05-10T21  avg= 4.2%  max=26.0%  — minor spike, traffic surge
  2026-05-10T22  avg= 3.7%  max=21.0%
  2026-05-12T00  avg= 4.9%  max=99.5%  🔴 ← CPU maxed, health check started failing
```

**What likely happened:** At 05:30 IST today a process (cron job, plugin update, WP-Cron, or a heavy request) pegged the CPU. Since this is a t3.medium, it has a CPU credit burst mechanism — once credits are exhausted, sustained high CPU drops to baseline (20%). The Nginx `/health` endpoint timeout during the spike caused ALB to mark it unhealthy and it has not recovered.

**Immediate diagnosis commands** (run on instance via bastion):
```bash
# Check what's running
top -b -n 1 | head -20

# Check PHP-FPM status
sudo systemctl status php-fpm
sudo cat /var/log/php-fpm/error.log | tail -50

# Check if WP-Cron is runaway
sudo ps aux | grep wp-cron

# Check Nginx
sudo systemctl status nginx
sudo tail -100 /var/log/nginx/error.log

# CPU credit balance (from CloudWatch, not on instance)
# aws cloudwatch get-metric-statistics --metric-name CPUCreditBalance ...
```

### 1.2 ECS Node Load Imbalance

ECS-Tenxyou-2 and ECS-Saleor-3 are nearly idle (0.3% CPU) while other nodes in the same cluster run at 6-8%. This suggests task placement is not balanced across container instances. Review ECS task placement strategy — use `spread` by `instanceId` to distribute load.

---

## 2. ECS Service CPU & Memory

> **Memory here is accurate** — ECS reports container-level memory reservation utilization natively, no agent required.

### 2.1 PROD-Tenxyou Cluster

#### PROD-tenxyou-fe-service (2 tasks running)

| Metric | 2-Day Avg | Peak | Peak Hour (UTC) |
|---|---|---|---|
| CPU Utilization | 13.6% | **99.7%** | 2026-05-10T21 (02:30 IST May 11) |
| Memory Utilization | 13.6% | 19.4% | 2026-05-11T20 |

**CPU spike on FE at 21:00 UTC May 10:**  
Frontend ECS service hit 99.73% CPU exactly when frontend traffic surged to **154,620 requests/hour** (highest of the period). This caused the auto-scaling AlarmLow to go into ALARM state — it's not the scale-in trigger firing, it's a scale-out event that was needed but may have been slow.

```
FE CPU Hourly (IST = UTC+5:30):
  05-10T19 UTC (00:30 IST)    5.5%  avg
  05-10T20 UTC (01:30 IST)    6.6%  avg
  05-10T21 UTC (02:30 IST)   22.2%  avg  max=99.7%  🔴 ← SPIKE
  05-10T22 UTC (03:30 IST)   21.3%  avg  max=90.7%  🔴
  05-10T23 UTC (04:30 IST)   11.8%  avg  ← recovered
```

#### PROD-tenxyou-be-service (3 tasks running)

| Metric | 2-Day Avg | Peak | Status |
|---|---|---|---|
| CPU Utilization | 3.8% | 30.2% | ✅ Healthy |
| Memory Utilization | 6.6% | 8.0% | ✅ Very low memory pressure |

BE memory at only 6.6% average suggests either the memory limit is over-provisioned, or the service is stateless and lean.

### 2.2 PROD-Saleor-backend Cluster

#### PROD-Saleor-API-service (5 tasks running)

| Metric | 2-Day Avg | Peak | Peak Hour (UTC) |
|---|---|---|---|
| CPU Utilization | 4.2% | **100.6%** | 2026-05-10T23 (04:30 IST May 11) |
| Memory Utilization | 31.4% | 34.2% | 2026-05-11T18 |

**CPU spike on Saleor API at 23:00 UTC May 10:**  
The 100.6% figure is a CloudWatch artifact — ECS service-level CPU > 100% occurs when one container in a multi-task service saturates a full vCPU while others are near-idle. The actual single peak was 51.05% in that hour. Memory is stable at 31.4%, which is healthy.

#### PROD-Saleor-Celery-Beat-service (1 task running)

| Metric | 2-Day Avg | Peak | Status |
|---|---|---|---|
| CPU Utilization | 0.3% | 0.8% | ✅ Normal for scheduler |
| Memory Utilization | 12.3% | 12.3% | ✅ Flat — stable |

---

## 3. ALB — Traffic, Errors & Latency

### 3.1 PROD-Tenxyou-ALB (Backend API: Tenxyou + Saleor)

| Metric | 2-Day Total | Hourly Avg | Peak Hour |
|---|---|---|---|
| Total Requests | 1,441,360 | 30,028/hr | 49,762 (05-10T11 UTC) |
| 2xx Responses | 1,367,345 | 28,486/hr | — |
| 4xx Errors | 20,820 | 434/hr | 1,257 (05-10T09 UTC) |
| 5xx Errors (Target) | 5,634 | 117/hr | 264 (05-11T23 UTC) |
| 5xx Errors (ELB) | 39 | 0.8/hr | 3 max | 
| Avg Response Time | 100ms | — | 100ms max |
| Active Connections | 302,043 total | 6,292/hr | 8,161 |
| Processed Data | 153 GB | 3.2 GB/hr | 5.75 GB |

**5xx Error Rate:** 5,634 / 1,441,360 = **0.39%** — above acceptable threshold (target <0.1%)

**5xx Trend Analysis — WORSENING:**
```
Backend 5xx Per Hour (UTC):
  May 10 peak:  233 at 11:00 UTC (16:30 IST)
  May 11 peak:  264 at 23:00 UTC (04:30 IST May 12)  ← new high, escalating overnight
  
  May 11 evening pattern (IST = UTC+5:30):
    22:00 UTC (03:30 IST):  219  ⚠️
    23:00 UTC (04:30 IST):  264  ⚠️ highest observed
  
  → 5xx count is INCREASING over the two-day window
```

**Latency:** Backend API average response time is a flat **100ms** throughout both days with minimal variance. This is healthy and suggests the application layer is not the bottleneck for the 5xx errors — they're likely logic/data errors, not timeouts.

### 3.2 prod-tenxyou-fe-alb (Frontend: Website + WordPress + Aboutus)

| Metric | 2-Day Total | Hourly Avg | Peak Hour |
|---|---|---|---|
| Total Requests | 4,404,976 | 91,770/hr | 182,482 (05-11T22 UTC) |
| 2xx Responses | 4,234,282 | 88,214/hr | 175,636 |
| 4xx Errors | 142,901 | 2,977/hr | 6,248 |
| 5xx Errors (Target) | 9 | ~0/hr | 8 max |
| 5xx Errors (ELB) | 814 | 17/hr | 93 max |
| Avg Response Time | <10ms | — | 100ms spike |
| Active Connections | 1,138,562 total | 23,720/hr | 32,888 |
| Processed Data | 293 GB | 6.1 GB/hr | 12.2 GB |

**Traffic Growth — May 11 significantly higher than May 10:**
```
Frontend Request Volume (IST peak hours):
  May 10 IST daytime peak:  ~104,000/hr (11:00-17:00 IST range)
  May 10 IST evening spike: 154,620/hr at 02:30 IST May 11  ← traffic burst
  
  May 11 IST daytime:       130,000-160,000/hr (consistent growth)
  May 11 IST evening peak:  182,482/hr at 03:30 IST May 12  ← new daily record
```

**Observation:** Frontend traffic grew ~75% from daytime May 10 to evening May 11. The 814 ELB-level 5xx errors (not target 5xx) are the ALB returning 5xx itself — this typically indicates connection issues to targets (502 gateway errors when container is starting, etc.).

**4xx Errors:** 142,901 over 2 days is high. At 2,977/hr average, this suggests either broken links/missing assets, misconfigured redirects, or bot traffic attempting non-existent paths.

### 3.3 ALB 5xx Hourly Breakdown — Backend API

```
UTC Hour     |   5xx | Trend
-------------|-------|------
05-10T05     |    50 | ██████
05-10T06     |    33 | ████
05-10T07     |    92 | ████████████
05-10T08     |   107 | ██████████████
05-10T09     |   130 | █████████████████
05-10T10     |   108 | ██████████████
05-10T11     |   233 | ████████████████████████████████ ← May 10 peak (16:30 IST)
05-10T12     |   122 | ████████████████
05-10T13     |   165 | █████████████████████
05-10T17     |   157 | ████████████████████
05-10T21     |   177 | ███████████████████████
[night UTC / early morning IST: drops to 10-72]
05-11T07     |   113 | ███████████████
05-11T09     |   155 | ████████████████████
05-11T10     |   204 | █████████████████████████████ ← 15:30 IST
05-11T12     |   153 | ████████████████████
05-11T16     |   172 | ███████████████████████
05-11T20     |   170 | ███████████████████████
05-11T21     |   175 | ████████████████████████
05-11T22     |   219 | ████████████████████████████████
05-11T23     |   264 | ████████████████████████████████████ ← highest (04:30 IST May 12)
```

**Pattern:** 5xx errors follow traffic — higher during IST business hours (05:30-12:00 UTC = 11:00-17:30 IST) and are worsening over the two days. This points to an application-level issue in the backend API that degrades under load.

---

## 4. RDS Database Metrics

> **RDS metrics come from built-in CloudWatch integration — no agent needed.**

### 4.1 erp-prod-db (MariaDB 10.6.24 — db.m5.2xlarge, 32GB RAM, 150GB io2)

| Metric | 2-Day Avg | Peak | Min | Assessment |
|---|---|---|---|---|
| CPU Utilization | 2.7% | 4.1% | 1.9% | ✅ Very low |
| Freeable Memory | 18.2 GB | 18.4 GB | 18.1 GB | ✅ 56.9% free |
| Free Storage Space | 122.5 GB | 122.6 GB | 122.3 GB | ✅ 81.6% free |
| Database Connections | 2.8 avg | 6.5 max | 1.3 min | ⚠️ Suspiciously low |
| Read IOPS | 0.3/s | 0.5/s | 0.3/s | ✅ Near zero |
| Write IOPS | 102.3/s | 199.1/s | 88.7/s | ✅ Normal, 3.4% of 3000 provisioned |
| Read Latency | 0.1ms | 0.3ms | 0ms | ✅ Excellent |
| Write Latency | 0.4ms | 0.6ms | 0.3ms | ✅ Excellent |
| Replica Lag | N/A (primary) | — | — | — |

**Observation — Low connections:** Only 2.8 average connections on a production ERP database serving a `c5a.4xlarge` ERP server is unusual. Either the application uses a connection pooler (PgBouncer/ProxySQL) and connections are not being tracked at the RDS level, or the ERP is less active than expected. Verify that the application is actually connecting successfully.

**Storage is write-heavy:** WriteIOPS at 102/s vs ReadIOPS at 0.3/s confirms ERP is write-dominated. Storage at 122.5GB free of 150GB (81.6% free) is healthy, but watch this — io2 max autoscale is set to 1TB.

### 4.2 erp-prod-read-replica (MariaDB — db.m5.large, 8GB RAM, 150GB io2)

| Metric | 2-Day Avg | Peak | Min | Assessment |
|---|---|---|---|---|
| CPU Utilization | 3.1% | 6.3% | 2.8% | ✅ Low |
| **Freeable Memory** | **0.93 GB** | **0.95 GB** | **0.88 GB** | **🔴 CRITICAL — 11.6% free** |
| Free Storage Space | 122.6 GB | 122.7 GB | 122.4 GB | ✅ 81.7% free |
| Database Connections | ~0 avg | 0.08 max | 0 | ⚠️ Nobody is reading from this replica |
| Read IOPS | 15.3/s | 178.2/s | 3.9/s | ✅ Light read load |
| Write IOPS | 46.5/s | 214.9/s | 34.3/s | — (replication writes) |
| **Replica Lag** | **1.68s avg** | **38.3s max** | **0s** | **🔴 38-second spike** |

**Memory is critically low:**  
db.m5.large has 8GB RAM. With only 0.93GB freeable (11.6%), the OS and MySQL buffer pool are consuming ~7GB. This means:
- Buffer pool is likely sized at or near the instance's memory limit
- OOM kills are a risk if memory pressure increases
- The 38-second replica lag spike is likely caused by memory pressure causing I/O thrashing

**Replica lag spike of 38 seconds:** This means at peak, read queries against the replica could be reading data that is 38 seconds stale. If any application code reads from this replica for critical data, it was reading stale data during those windows.

**Nobody is reading from the replica:** DatabaseConnections averages ~0. The read replica is running but no application is routing reads to it. You're paying for db.m5.large (~$120/month) with no utilization. Either connect reads to it or investigate why it's not used.

### 4.3 saleor-strapi-db (PostgreSQL 17.4 — db.m6gd.4xlarge, 64GB RAM, 100GB gp3)

| Metric | 2-Day Avg | Peak | Min | Assessment |
|---|---|---|---|---|
| CPU Utilization | 0.97% | 1.4% | 0.5% | ✅ Very low |
| Freeable Memory | 42.1 GB | 42.2 GB | 42.2 GB | ✅ 65.8% free |
| Free Storage Space | 94.3 GB | 94.4 GB | 94.2 GB | ✅ 94.3% free |
| Database Connections | 6.2 avg | 8.1 max | 5.1 min | ✅ Low but consistent |
| Read IOPS | 0.27/s | 0.29/s | 0.26/s | ✅ Minimal reads |
| Write IOPS | 5.9/s | 9.9/s | 3.1/s | ✅ Light writes |
| Write Latency | 1.0ms | 1.3ms | 0.9ms | ✅ Normal |

**Observation — Oversized instance:** At <1% CPU and 65% free memory on a `db.m6gd.4xlarge`, this instance is significantly over-provisioned. The m6gd has local NVMe SSD which explains why it was chosen, but at this utilization level a `db.m6gd.xlarge` or `db.m6g.2xlarge` would suffice. Potential monthly savings: ~$800-1,200/month.

### 4.4 strapi-db-read-replica (PostgreSQL 17.4 — db.m6gd.4xlarge, 64GB RAM)

| Metric | 2-Day Avg | Peak | Min | Assessment |
|---|---|---|---|---|
| CPU Utilization | 0.47% | 0.87% | 0.36% | ✅ Extremely low |
| Freeable Memory | 42.3 GB | 42.4 GB | 42.3 GB | ✅ 66.1% free |
| **Database Connections** | **0 avg** | **0 max** | **0 min** | **🔴 Zero usage — unused** |
| **Replica Lag** | **7.37s avg** | **22.1s max** | **1.5s min** | **⚠️ Consistently high** |

**Zero connections + high replica lag:** This replica has never been connected to during the entire 48-hour window. Despite no read traffic, it has 7.37 seconds of average replica lag, meaning the database writes are consistently arriving 7+ seconds late. If reads are ever directed here, they would see significantly stale data. Investigate WAL sender configuration on primary.

### 4.5 preprod-tenxyou-saleor-db (PostgreSQL 17.4 — db.m5.large, 8GB RAM)

| Metric | 2-Day Avg | Peak | Assessment |
|---|---|---|---|
| CPU Utilization | 3.0% | 3.1% | ✅ Stable |
| Freeable Memory | 4.63 GB | 4.64 GB | ✅ 57.9% free |
| Free Storage Space | 94.8 GB | 94.8 GB | ✅ 94.8% free |
| Database Connections | 3.0 avg | 3.2 max | ✅ Very stable |
| Write IOPS | 2.4/s | 2.5/s | ✅ Minimal activity |

Preprod database is stable and lightly used.

---

## 5. ElastiCache Redis Metrics

### 5.1 erp-prod-cache (Primary: erp-prod-cache-001, Replica: erp-prod-cache-002)

#### Primary Node (erp-prod-cache-001)

| Metric | 2-Day Value | Assessment |
|---|---|---|
| CPU Utilization | 2.0% avg, 2.3% max | ✅ Healthy |
| Cache Memory Used | 58.7 MB avg, 64.1 MB max | ✅ Very low (cache.r7g.large = 13.07GB available) |
| Memory Utilization | ~0.4% of available | ✅ Nearly empty |
| Cache Hits | 3,911,690 total (48h) | ✅ ~81,493/hr |
| Cache Misses | 209,196 total (48h) | — |
| **Cache Hit Rate** | **94.9%** | ✅ Good |
| Current Connections | 111.8 avg, 114.5 max | ✅ Stable |
| Evictions | 0 | ✅ No memory pressure |
| Network In | 7.1 GB total | — |
| Network Out | 68.1 GB total | — |
| Replication Lag | 0ms | ✅ Sync |

#### Replica Node (erp-prod-cache-002)

| Metric | Value | Assessment |
|---|---|---|
| Cache Hits | 0 | ⚠️ Replica receives no reads — application only writes to primary |
| Connections | 5.9 avg | Only monitoring connections |
| Replication Lag | 0ms | ✅ In sync |

**Observation:** The erp-prod cache has a replica that nobody reads from (0 hits on erp-prod-cache-002). The application connects only to the primary. The replica exists purely for failover, which is the correct setup.

**Only 58MB of 13GB used:** The ERP Redis cache is using less than 0.5% of available memory. Either the cache TTLs are short and data expires quickly, or the cache is not caching as much as it could. This is not a problem per se, but indicates potential for increasing cache coverage to reduce DB load.

### 5.2 saleor-prod-cache-redis (Single node: saleor-prod-cache-redis-001)

| Metric | 2-Day Value | Assessment |
|---|---|---|
| CPU Utilization | 1.52% avg, 1.65% max | ✅ Healthy |
| **Cache Memory Used** | **538 MB avg, 588 MB max** | ⚠️ 4.1% of 13.07GB — moderate but growing |
| Cache Hits | 16,220,753 total (48h) | ✅ ~338,015/hr |
| Cache Misses | 136,516 total (48h) | — |
| **Cache Hit Rate** | **99.2%** | ✅ Excellent |
| Current Connections | 48.2 avg, 74.6 max | ✅ Healthy |
| Evictions | 0 | ✅ No pressure |
| Network Out | 332 GB total (48h) | ⚠️ 6.9 GB/hr outbound — high cache read volume |

**Excellent cache performance:** 99.2% hit rate means the Saleor application is very cache-efficient. 16.2M hits over 48 hours vs 136K misses is outstanding.

**Memory growing:** From 538MB avg to 588MB max — not alarming, but monitor this trend. At current growth rate it will take many months to approach limits, but since there's no replica, an OOM or node failure means all 538MB of cached state is lost instantly.

**Network Out 332GB:** Saleor Redis is serving 6.9GB/hour of cached data. This is the highest outbound traffic of any component — confirms Redis is the true performance backbone of the Saleor stack.

---

## 6. Backup Space Utilization

### 6.1 RDS Automated Snapshots

| Database | Snapshot Count | Storage Per Snapshot | Estimated Backup Storage |
|---|---|---|---|
| erp-prod-db | 9 snapshots (7-day retention) | 150 GB | ~1,350 GB |
| preprod-tenxyou-saleor-db | 10 snapshots (7-day retention) | 100 GB | ~1,000 GB |
| saleor-strapi-db | 10 snapshots (7-day retention) | 100 GB | ~1,000 GB |
| erp-prod-read-replica | 0 (no retention on replica) | — | 0 |
| preprod-saleor-read-replica | 0 | — | 0 |
| strapi-db-read-replica | 0 | — | 0 |

**Total estimated RDS snapshot storage: ~3,350 GB (3.35 TB)**  

> **Cost note:** AWS provides free backup storage equal to the sum of your provisioned database storage (150+100+100 = 350 GB free). Storage beyond that is $0.095/GB-month. Actual snapshot compression can reduce physical size significantly for delta-based snapshots. Check actual snapshot sizes in the console for precise billing.

**Latest snapshots:** All three primary databases have snapshots from 2026-05-11 — confirmed current.

### 6.2 EBS Snapshots

No manual EBS snapshots were detected in the data collection. The automated snapshot count from RDS is tracked above.

> **Gap:** There are no EBS snapshots for the EC2 instances running self-managed databases (`tenxyou-db-prod`, `custom-db-read-replica`) and WordPress. These instances have no automated backup. If terminated, data is permanently lost.

### 6.3 S3 Storage (Not Pulled — CloudWatch S3 metrics are daily-only)

CloudWatch S3 metrics (`BucketSizeBytes`) are published once per day at midnight UTC with a 1-day lag. Pulling these for May 10-11 is not meaningful in a real-time report.

**Estimated active buckets and usage pattern:**
| Bucket | Traffic Indicator |
|---|---|
| saleor-prod-assets | Likely largest — product images, media |
| tenxyou-prod-assets | Frontend app bundles |
| tenxyou-website-public-assets | Static website files |
| tenxyou-prod-alb-access-logs | ~293 GB processed by ALB over 2 days → significant log volume |

---

## 7. Key Findings Summary

### 7.1 Active Issues Observed in This Period

| # | Severity | Finding | When | Impact |
|---|---|---|---|---|
| 1 | 🔴 Critical | WordPress CPU hit 99.5% | 2026-05-12 00:00 UTC (05:30 IST today) | Health check failed, TG unhealthy now |
| 2 | 🔴 Critical | ECS FE CPU hit 99.7% | 2026-05-10 21:00 UTC (02:30 IST May 11) | Service degradation during traffic surge |
| 3 | 🔴 Critical | erp-prod-read-replica memory at 11.6% free | Persistent | OOM risk; 38s replica lag spike |
| 4 | ❌ High | Backend API 5xx errors: 5,634 over 48h (0.39% rate) | Persistent, worsening | API errors reaching users |
| 5 | ❌ High | Backend 5xx trend increasing | Max 50→264 over 2 days | Getting worse, not better |
| 6 | ⚠️ Warning | Saleor API ECS CPU spike to 100.6% | 2026-05-10 23:00 UTC | Container-level CPU saturation |
| 7 | ⚠️ Warning | strapi-db-read-replica: 7.37s avg replica lag | Persistent | Stale reads if ever used |
| 8 | ⚠️ Warning | Frontend 4xx errors: 142,901 over 2 days | Persistent | Possible broken links, bot traffic |

### 7.2 What Is Healthy

| Component | Status | Key Metric |
|---|---|---|
| Backend API latency | ✅ Healthy | Flat 100ms, no degradation |
| Frontend latency | ✅ Healthy | <10ms (likely CDN-aided) |
| ERP database (primary) | ✅ Healthy | 2.7% CPU, 82% storage free, sub-ms latency |
| Saleor Redis cache | ✅ Excellent | 99.2% hit rate, 0 evictions |
| ERP Redis cache | ✅ Good | 94.9% hit rate, 0 evictions |
| All ECS services | ✅ Running | All at desired count, no pending tasks |
| Celery Beat scheduler | ✅ Stable | 0.3% CPU, flat memory |
| Saleor API memory | ✅ Healthy | 31.4% avg utilization |
| ERP database storage | ✅ Healthy | 81.6% free, auto-grow to 1TB configured |

---

## 8. Monitoring Gaps & What to Add

| Gap | Priority | Fix |
|---|---|---|
| EC2 Memory | 🔴 Critical | Install CloudWatch Agent, add `mem_used_percent` |
| EC2 Disk space | 🔴 Critical | Add `disk_used_percent` for `/` and data volumes |
| WordPress Nginx 5xx count | ❌ High | Add nginx access log metrics via CW Agent |
| ALB Healthy/Unhealthy host count | ❌ High | Add `HealthyHostCount` + `UnHealthyHostCount` alarms per TG |
| RDS read replica memory alarm | ❌ High | Alarm on `FreeableMemory < 1GB` for erp-prod-read-replica |
| Redis memory utilization % | ⚠️ Medium | Add alarm on `DatabaseMemoryUsagePercentage > 80%` |
| EC2 CPU credit balance | ⚠️ Medium | Add alarm for t2/t3 instances when `CPUCreditBalance < 20` |
| Replication lag alarm | ⚠️ Medium | Add alarm on `ReplicaLag > 10s` for both replicas |

---

*Generated: 2026-05-12 | Period covered: 2026-05-10 to 2026-05-11 UTC | Data: CloudWatch 1-hour aggregation*
