# TenXYou AWS Infrastructure Health Report
**Account ID:** 565386896838  
**Report Date:** 2026-05-12  
**Audited By:** Read-Only_vishv (IAM ReadOnlyAccess)  
**Primary Region:** ap-south-1 | **Secondary Region:** us-east-1  
**Report Type:** First Baseline Health Audit  

---

## Executive Summary

| Category | Status | Critical Issues | Warnings |
|---|---|---|---|
| Compute (EC2/ECS) | ⚠️ Degraded | 1 | 2 |
| Database (RDS) | ⚠️ Warning | 1 | 3 |
| Cache (ElastiCache) | ⚠️ Warning | 0 | 3 |
| Storage (EBS/S3) | 🔴 At Risk | 1 | 3 |
| Networking (VPC/ALB/R53) | ⚠️ Warning | 0 | 2 |
| Security (SGs/IAM/Certs) | 🔴 At Risk | 3 | 4 |
| Observability (CW/Monitoring) | 🔴 At Risk | 0 | 4 |
| CDN (CloudFront) | ⚠️ Warning | 0 | 1 |

**Overall: 6 Critical Issues — 22 Warnings — Immediate action required on security and wordpress health.**

---

## Table of Contents
1. [EC2 Instances](#1-ec2-instances)
2. [ECS Clusters & Services](#2-ecs-clusters--services)
3. [RDS Databases](#3-rds-databases)
4. [ElastiCache (Redis)](#4-elasticache-redis)
5. [Storage — EBS Volumes](#5-storage--ebs-volumes)
6. [Storage — S3 Buckets](#6-storage--s3-buckets)
7. [Load Balancers & Target Groups](#7-load-balancers--target-groups)
8. [CloudFront CDN](#8-cloudfront-cdn)
9. [Networking (VPC / NAT / EIP)](#9-networking-vpc--nat--eip)
10. [DNS — Route 53](#10-dns--route-53)
11. [SSL/TLS Certificates (ACM)](#11-ssltls-certificates-acm)
12. [Security Groups Audit](#12-security-groups-audit)
13. [CloudWatch Alarms & Monitoring](#13-cloudwatch-alarms--monitoring)
14. [Findings Summary & Action Plan](#14-findings-summary--action-plan)

---

## 1. EC2 Instances

### 1.1 ap-south-1 (Production) — 17 Instances

| Name | Instance ID | Type | State | AZ | Public IP | IMDSv2 | Monitoring |
|---|---|---|---|---|---|---|---|
| prod-bastion | i-054c50bc4f63d90d7 | t3a.small | ✅ running | ap-south-1a | 43.205.124.202 | ✅ required | ❌ disabled |
| erp-prod | i-0b625f2bbc1955b52 | c5a.4xlarge | ✅ running | ap-south-1a | 3.7.129.182 (EIP) | ✅ required | ❌ disabled |
| strapi-prod | i-0b27df1cf9ea9691a | t3a.2xlarge | ✅ running | ap-south-1a | 3.6.186.108 (EIP) | ✅ required | ❌ disabled |
| strapi-preprod | i-0d90f6f9cfc3ac3fe | t3a.2xlarge | ✅ running | ap-south-1b | 3.110.45.144 | ✅ required | ❌ disabled |
| saleor-prod-dashboard | i-0f617410782147d80 | t3.medium | ✅ running | ap-south-1a | 3.108.148.58 (EIP) | ✅ required | ❌ disabled |
| saleor-prod-worker-be | i-0235e0c2cb0c20c13 | t3a.large | ✅ running | ap-south-1a | 43.205.213.92 | ✅ required | ❌ disabled |
| WEBSITE-wordpress-aboutus | i-0fc2dc16732238cd6 | t3.medium | ✅ running | ap-south-1a | 3.6.59.24 (EIP) | ✅ required | ❌ disabled |
| tenxyou-db-prod [CUSTOM DB] | i-02e7d5b8ee780cc3c | t2.xlarge | ✅ running | ap-south-1a | 65.2.188.14 | ✅ required | ❌ disabled |
| Custom-DB-Read-Replica | i-0a525b4a77f8e916f | t2.xlarge | ✅ running | ap-south-1a | 65.0.184.134 | ✅ required | ❌ disabled |
| Nginx-Server-path-based-routing | i-081242d031f1c02f5 | t2.micro | ✅ running | ap-south-1a | 65.2.179.195 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Tenxyou (1) | i-05075c06d16fc40b4 | t3.xlarge | ✅ running | ap-south-1a | 13.233.92.1 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Tenxyou (2) | i-0c2a1c762e73a9692 | t3.xlarge | ✅ running | ap-south-1b | 13.203.218.62 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Tenxyou (3) | i-06ac274f28b87c39a | t3.xlarge | ✅ running | ap-south-1b | 13.235.80.186 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Saleor-backend (1) | i-0ebeb41fd42d9892d | t3.xlarge | ✅ running | ap-south-1a | 13.201.56.6 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Saleor-backend (2) | i-05c391425420a8d84 | t3.xlarge | ✅ running | ap-south-1b | 3.109.55.192 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Saleor-backend (3) | i-07ec68aee87fb47d9 | t3.xlarge | ✅ running | ap-south-1b | 3.111.32.229 | ✅ required | ❌ disabled |
| ECS Instance - PROD-Saleor-backend (4) | i-03eb63b3774190651 | t3.xlarge | ✅ running | ap-south-1a | 13.234.77.30 | ✅ required | ❌ disabled |

**ap-south-1 Summary:** 17 running, 0 stopped. All IMDSv2 enforced. **Zero EC2 instances have detailed monitoring enabled.**

### 1.2 us-east-1 (Staging/Testing) — 3 Instances

| Name | Instance ID | Type | State | AZ | Public IP | IMDSv2 | Monitoring |
|---|---|---|---|---|---|---|---|
| testing-nginx | i-067b26b3fd722c292 | t2.micro | ✅ running | us-east-1a | 18.212.52.158 | ✅ required | ❌ disabled |
| wordpress-server | i-08243b86e06d6cb74 | t2.small | ✅ running | us-east-1a | 3.92.61.174 | ✅ required | ❌ disabled |
| ECS Instance - STAGING-tenxyou | i-06510afef3eae3daa | t2.medium | ✅ running | us-east-1b | private only | ✅ required | ❌ disabled |

### 1.3 EC2 Observations

| # | Severity | Finding |
|---|---|---|
| 1 | ⚠️ Warning | **Zero EC2 instances have detailed CloudWatch monitoring.** Basic monitoring gives 5-minute granularity only — useless for incident response. |
| 2 | ⚠️ Warning | **7 prod ECS instances have public IPs.** ECS nodes should be in private subnets only; traffic routed via ALB. |
| 3 | ℹ️ Info | `tenxyou-db-prod [CUSTOM DB]` and `Custom-DB-Read-Replica` appear to be self-managed databases on EC2 (t2.xlarge) running alongside RDS. Needs lifecycle ownership documented. |
| 4 | ✅ Good | IMDSv2 enforced on all 20 instances. |

---

## 2. ECS Clusters & Services

### 2.1 PROD-Tenxyou (ap-south-1)

| Attribute | Value |
|---|---|
| Status | ✅ ACTIVE |
| Container Instances | 3 × t3.xlarge |
| Running Tasks | 5 |
| Pending Tasks | 0 |

| Service | Desired | Running | Pending | Task Definition | Rollout State |
|---|---|---|---|---|---|
| PROD-tenxyou-fe-service | 2 | 2 | 0 | PROD-tenxyou-fe:**276** | ✅ COMPLETED |
| PROD-tenxyou-be-service | 3 | 3 | 0 | PROD-tenxyou-be:**230** | ✅ COMPLETED |

### 2.2 PROD-Saleor-backend (ap-south-1)

| Attribute | Value |
|---|---|
| Status | ✅ ACTIVE |
| Container Instances | 4 × t3.xlarge |
| Running Tasks | 8 |
| Pending Tasks | 0 |

| Service | Desired | Running | Pending | Task Definition | Rollout State |
|---|---|---|---|---|---|
| PROD-Saleor-API-service | 5 | 5 | 0 | PROD-Saleor-API:**17** | ✅ COMPLETED |
| PROD-Saleor-Celery-Beat-service | 1 | 1 | 0 | PROD-Saleor-Celery-Beat:**9** | ✅ COMPLETED |
| PROD-Saleor-jaeger-service | 1 | 1 | 0 | PROD-Saleor-jaeger:**7** | ✅ COMPLETED |
| PROD-Saleor-mailpit-service | 1 | 1 | 0 | PROD-Saleor-mailpit:**6** | ✅ COMPLETED |

### 2.3 STAGING-tenxyou (us-east-1)

| Service | Status |
|---|---|
| frontend-staging | Active (1 instance) |

### 2.4 ECS Observations

| # | Severity | Finding |
|---|---|---|
| 1 | ✅ Good | All ECS services running at desired count. No pending tasks. All rollouts completed. |
| 2 | ⚠️ Warning | **Jaeger and Mailpit running in production cluster** — distributed tracing (Jaeger) and mail testing (Mailpit) are dev/debug tools. Verify these are intentional and not exposed externally. |
| 3 | ⚠️ Warning | **Task definition revisions are high** (fe:276, be:230) — suggests frequent deployments with no cleanup. Old task definitions accumulate but don't auto-delete. |

---

## 3. RDS Databases

### 3.1 Instance Inventory

| Identifier | Engine | Class | Status | AZ | Multi-AZ | Storage | Encrypted | Public | Deletion Protection | Backup Retention |
|---|---|---|---|---|---|---|---|---|---|---|
| erp-prod-db | MariaDB 10.6.24 | db.m5.2xlarge | ✅ available | ap-south-1a | ❌ No | 150GB io2 (3000 IOPS) | ✅ KMS | ❌ No | ✅ Yes | 7 days |
| erp-prod-read-replica | MariaDB 10.6.24 | db.m5.large | ✅ replicating | ap-south-1b | ❌ No | 150GB io2 | ✅ KMS | 🔴 **YES** | ✅ Yes | 0 days |
| preprod-tenxyou-saleor-db | PostgreSQL 17.4 | db.m5.large | ✅ available | ap-south-1a | ❌ No | 100GB gp3 | ✅ KMS | ❌ No | ✅ Yes | 7 days |
| preprod-saleor-read-replica | PostgreSQL 17.4 | db.m5.large | ✅ replicating | ap-south-1b | ❌ No | 100GB gp3 | ✅ KMS | ❌ No | ❌ **No** | 0 days |
| saleor-strapi-db | PostgreSQL 17.4 | db.m6gd.4xlarge | ✅ available | ap-south-1a | ❌ No | 100GB gp3 | ✅ KMS | ❌ No | ❌ **No** | 7 days |
| strapi-db-read-replica | PostgreSQL 17.4 | db.m6gd.4xlarge | ✅ replicating | ap-south-1a | ❌ No | 100GB gp3 | ✅ KMS | ❌ No | ✅ Yes | 0 days |

### 3.2 Backup Status (Automated Snapshots)

| Identifier | Snapshot Count | Latest Snapshot |
|---|---|---|
| erp-prod-db | 9 | 2026-05-11 ✅ |
| preprod-tenxyou-saleor-db | 10 | 2026-05-11 ✅ |
| saleor-strapi-db | 10 | 2026-05-11 ✅ |
| erp-prod-read-replica | 0 (replica, expected) | — |
| preprod-saleor-read-replica | 0 (replica, expected) | — |
| strapi-db-read-replica | 0 (replica, expected) | — |

### 3.3 RDS CA Certificate Expiry

| Identifier | CA | Expires |
|---|---|---|
| erp-prod-db | rds-ca-rsa2048-g1 | 2027-02-27 ✅ |
| erp-prod-read-replica | rds-ca-rsa2048-g1 | 2027-05-07 ✅ |
| preprod-tenxyou-saleor-db | rds-ca-rsa2048-g1 | 2027-03-31 ✅ |
| preprod-saleor-read-replica | rds-ca-rsa2048-g1 | 2027-05-07 ✅ |
| saleor-strapi-db | rds-ca-rsa2048-g1 | 2027-04-11 ✅ |
| strapi-db-read-replica | rds-ca-rsa2048-g1 | 2027-05-07 ✅ |

### 3.4 RDS Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 🔴 Critical | **erp-prod-read-replica is PubliclyAccessible = true.** A production MariaDB read replica is directly reachable from the internet. Must be set to false — access it via bastion or VPN. |
| 2 | 🔴 Critical | **Zero RDS instances are Multi-AZ.** If the primary AZ (ap-south-1a) has an outage, all three primary databases go down. |
| 3 | ❌ High | **saleor-strapi-db has deletion protection disabled.** This is a production Postgres db.m6gd.4xlarge instance. An accidental `rds delete-db-instance` would destroy it. |
| 4 | ❌ High | **preprod-saleor-read-replica has deletion protection disabled.** |
| 5 | ✅ Good | All RDS instances encrypted with KMS at rest. |
| 6 | ✅ Good | All primary instances have automated backups with recent snapshots (latest: 2026-05-11). |
| 7 | ✅ Good | All read replicas are actively replicating (Status: replicating). |
| 8 | ✅ Good | Performance Insights enabled on erp-prod-db, erp-prod-read-replica, preprod-saleor-read-replica, strapi-db-read-replica. |
| 9 | ⚠️ Warning | **IAM Database Authentication disabled on all instances.** Password-only auth — no short-lived credential enforcement. |

---

## 4. ElastiCache (Redis)

### 4.1 Replication Groups

| Group ID | Engine | Node Type | Nodes | AZ Distribution | Auto-Failover | Multi-AZ | At-Rest Enc | In-Transit Enc | Auth Token | Snapshot Retention |
|---|---|---|---|---|---|---|---|---|---|---|
| erp-prod-cache | Redis 7.1.0 | cache.r7g.large | 2 (1P + 1R) | 1a + 1b | ✅ Enabled | ❌ Disabled | ✅ Yes | ✅ Yes (required) | ❌ None | 3 days |
| saleor-prod-cache-redis | Redis 7.1.0 | cache.r7g.large | 1 (primary only) | ap-south-1b | ❌ Disabled | ❌ Disabled | ✅ Yes | ✅ Yes (required) | ❌ None | 1 day |

### 4.2 Node Endpoints

**erp-prod-cache:**
- Primary: `master.erp-prod-cache.tc40to.aps1.cache.amazonaws.com:6379`
- Reader: `replica.erp-prod-cache.tc40to.aps1.cache.amazonaws.com:6379`

**saleor-prod-cache-redis:**
- Primary: `master.saleor-prod-cache-redis.tc40to.aps1.cache.amazonaws.com:6379`

### 4.3 ElastiCache Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 🔴 Critical | **saleor-prod-cache-redis is a single node with no replica and no auto-failover.** If this node fails, the Saleor production stack loses its cache entirely. A cache miss storm would hit the database immediately. Add at least one read replica. |
| 2 | ❌ High | **AUTH token disabled on both caches.** Anyone who reaches the Redis endpoint on port 6379 inside the VPC can read/write without authentication. Enable AUTH token or Redis ACL. |
| 3 | ⚠️ Warning | **erp-prod-cache has auto-failover enabled but Multi-AZ disabled.** Failover works within the same AZ configuration but doesn't guarantee true AZ separation on failover. Enable Multi-AZ for guaranteed cross-AZ promotion. |
| 4 | ✅ Good | Both clusters use Redis 7.1.0 — current and actively maintained. |
| 5 | ✅ Good | Both clusters have at-rest and in-transit encryption enforced. |

---

## 5. Storage — EBS Volumes

### 5.1 Volume Inventory (ap-south-1)

| Volume ID | Size | Type | AZ | State | Encrypted | Attached To |
|---|---|---|---|---|---|---|
| vol-0e05e59dcc3db5ad7 | 50 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-054c50bc4f63d90d7 (prod-bastion) |
| vol-0acacbe2651a1888f | 150 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0b625f2bbc1955b52 (erp-prod) |
| vol-0a1ed0965e5816473 | 250 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0235e0c2cb0c20c13 (saleor-prod-worker-be) |
| vol-0911383bd203cafeb | 50 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0fc2dc16732238cd6 (WEBSITE-wordpress) |
| vol-078c8886d0ea4e569 | 100 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0b27df1cf9ea9691a (strapi-prod) |
| vol-057e177627d443a82 | 30 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0f617410782147d80 (saleor-prod-dashboard) |
| vol-07634055a633ba93b | 100 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-02e7d5b8ee780cc3c (tenxyou-db-prod) |
| vol-0267bbace6ac025a6 | 100 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-05075c06d16fc40b4 (ECS PROD-Tenxyou) |
| vol-0bd6cedd7934f0250 | 30 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-081242d031f1c02f5 (Nginx routing) |
| vol-048ba50a9b61aeae8 | 100 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0ebeb41fd42d9892d (ECS Saleor) |
| vol-09603993deea7213a | 100 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-0a525b4a77f8e916f (Custom-DB-Replica) |
| vol-02ab2ffafdea678eb | 100 GB | gp3 | ap-south-1b | in-use | 🔴 No | i-0c2a1c762e73a9692 (ECS PROD-Tenxyou) |
| vol-059288504dad68e7a | 100 GB | gp3 | ap-south-1b | in-use | 🔴 No | i-06ac274f28b87c39a (ECS PROD-Tenxyou) |
| vol-0c45b1ee3aba37916 | 30 GB | gp3 | ap-south-1b | in-use | 🔴 No | i-0d90f6f9cfc3ac3fe (strapi-preprod) |
| vol-0ccf7f8510f58606f | 100 GB | gp3 | ap-south-1b | in-use | 🔴 No | i-05c391425420a8d84 (ECS Saleor) |
| vol-0c73cf4a3d236a276 | 100 GB | gp3 | ap-south-1b | in-use | 🔴 No | i-07ec68aee87fb47d9 (ECS Saleor) |
| vol-0a09e88ffa56cbbbe | 100 GB | gp3 | ap-south-1a | in-use | 🔴 No | i-03eb63b3774190651 (ECS Saleor) |

**Total EBS Storage:** ~1,490 GB across 17 volumes. **0 of 17 volumes are encrypted.**

### 5.2 EBS Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 🔴 Critical | **All 17 EBS volumes are unencrypted.** This includes ERP data (150GB), Saleor media workers (250GB), WordPress content, and custom database instances. Non-compliance with data-at-rest security requirements. To fix: enable EBS encryption by default per-region, then snapshot → encrypted copy → replace volumes. |
| 2 | ⚠️ Warning | **All volumes are `DeleteOnTermination: true`.** If any EC2 instance is accidentally terminated, the root volume and its data are permanently deleted. For stateful servers (tenxyou-db-prod, wordpress, erp-prod), change to `DeleteOnTermination: false`. |

---

## 6. Storage — S3 Buckets

### 6.1 Bucket Inventory (13 buckets, all global)

| Bucket Name | Purpose | Versioning | Encryption | Public Access Block | Created |
|---|---|---|---|---|---|
| tenxyou-prod-assets | Prod app assets | ❌ Disabled | AES256 | ⚠️ Partial/Open | 2026-04-22 |
| tenxyou-website-public-assets | Website public assets | ❌ Disabled | AES256 | ⚠️ Partial/Open | 2026-04-22 |
| saleor-prod-assets | Saleor prod assets | ❌ Disabled | AES256 | ⚠️ Partial/Open | 2026-04-22 |
| saleor-media-private-prod | Saleor prod media (**private**) | ❌ Disabled | AES256 | ⚠️ Partial/Open | 2026-04-22 |
| saleor-staging-assets | Staging assets | ❌ Disabled | AES256 | ⚠️ Partial/Open | 2026-04-22 |
| saleor-media-private-preprod | Preprod media (**private**) | ❌ Disabled | AES256 | ⚠️ Partial/Open | 2026-04-22 |
| strapi-preprod-assets | Strapi preprod assets | Not checked | AES256 | Not checked | 2026-04-22 |
| saleor-preprod-assets | Saleor preprod assets | Not checked | AES256 | Not checked | 2026-04-22 |
| tenxyou-prod-alb-access-logs | ALB access logs | Not checked | AES256 | Not checked | 2026-04-22 |
| tenxyou-tf-state-bucket-ap-south-1 | Terraform state | ✅ Enabled | AES256 | ✅ **BLOCKED** | 2026-04-22 |
| account-cost-export-tenxyou | Cost export | Not checked | AES256 | Not checked | 2026-04-22 |
| athena-query-result-backendalb | Athena queries | Not checked | AES256 | Not checked | 2026-04-22 |
| daily-report-tenxyou | Daily reports | Not checked | AES256 | Not checked | 2026-04-21 |

### 6.2 S3 Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 🔴 Critical | **`saleor-media-private-prod` and `saleor-media-private-preprod` are named "private" but have partial/open public access block.** Media files (likely user-uploaded product images, invoices) may be directly reachable via S3 URL. Audit and enforce full public access block if CloudFront is the intended access path. |
| 2 | ❌ High | **Versioning disabled on all critical asset buckets.** Accidental overwrites or deletes are unrecoverable. Enable versioning on at minimum `saleor-media-private-prod` and `tenxyou-prod-assets`. |
| 3 | ⚠️ Warning | **ALB access logs bucket `tenxyou-prod-alb-access-logs` exists** — verify that ALB access logging is actually enabled on both ALBs and logs are flowing in. |
| 4 | ✅ Good | All buckets use server-side encryption (AES256). |
| 5 | ✅ Good | Terraform state bucket has versioning enabled and full public access blocked — correctly hardened. |
| 6 | ✅ Good | Separate buckets for prod, preprod, and staging assets — good isolation. |

---

## 7. Load Balancers & Target Groups

### 7.1 Application Load Balancers (ap-south-1)

| Name | ARN (short) | Scheme | State | VPC | AZs |
|---|---|---|---|---|---|
| PROD-Tenxyou-ALB | a7289dca7ebad844 | internet-facing | ✅ active | erpnext-vpc | ap-south-1a, ap-south-1b |
| prod-tenxyou-fe-alb | 20c56fcc92b492a0 | internet-facing | ✅ active | erpnext-vpc | ap-south-1a, ap-south-1b |

Both ALBs are dual-AZ — good.

### 7.2 Target Groups & Health Status

| Target Group | ALB | Protocol | Health Check Path | Healthy Threshold | Interval | Registered Targets | Health |
|---|---|---|---|---|---|---|---|
| PROD-saleor-api | PROD-Tenxyou-ALB | HTTP | /health/ | 5 | 30s | 5 | ✅ 5/5 healthy |
| PROD-tenxyou-be | PROD-Tenxyou-ALB | HTTP | /health | 5 | 30s | 3 | ✅ 3/3 healthy |
| PROD-tenxyou-fe | prod-tenxyou-fe-alb | HTTP | /health | 3 | 120s | 2 | ✅ 2/2 healthy |
| aboutus | prod-tenxyou-fe-alb | HTTP | / | 5 | 30s | 1 | ✅ 1/1 healthy |
| wordpress-site | prod-tenxyou-fe-alb | HTTP | /health | 5 | 30s | 1 | 🔴 **0/1 UNHEALTHY** |

### 7.3 ALB/TG Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 🔴 Critical | **`wordpress-site` target group has 0 healthy targets.** The WordPress server (`i-0fc2dc16732238cd6`, `WEBSITE-wordpress-aboutus`) is **failing its `/health` health check**. Traffic to the WordPress path via `prod-tenxyou-fe-alb` is currently being dropped or returning errors. Immediate investigation needed. Check: Nginx config for `/health` endpoint, WordPress running status, PHP-FPM, disk/memory on instance. |
| 2 | ⚠️ Warning | **`PROD-tenxyou-fe` health check interval is 120s with 90s timeout.** This is extremely lenient — an unhealthy target could receive traffic for up to 10 minutes (5 thresholds × 120s) before being pulled. Standard is 30s/5s. |
| 3 | ✅ Good | Both ALBs are dual-AZ (ap-south-1a + ap-south-1b). |
| 4 | ✅ Good | All non-WordPress target groups show 100% healthy targets. |

---

## 8. CloudFront CDN

### 8.1 Distributions

#### Distribution 1: `E3GXI4OPBT0UBV`
| Attribute | Value |
|---|---|
| Status | ✅ Deployed |
| Aliases | `api.tenxyou.com`, `api-saleor.tenxyou.com` |
| Origins | `prod-tenxyou-fe-alb` (HTTPS only), `PROD-Tenxyou-ALB` (HTTPS only) |
| WAF | ✅ `tenxyou_Rate_limiting` (WAF v2) |
| HTTPS Min Version | TLSv1.2_2021 ✅ |

#### Distribution 2: `E3VFT9H0BVWMF1`
| Attribute | Value |
|---|---|
| Status | ✅ Deployed |
| Aliases | `preprod.tenxyou.infinitelocus.com` |
| Origins | 7 origins: staging ELB, wordpress, nginx, saleor preprod, etc. |
| WAF | 🔴 **None** |
| HTTPS Min Version | TLSv1.2_2021 ✅ |

### 8.2 CloudFront Findings

| # | Severity | Finding |
|---|---|---|
| 1 | ⚠️ Warning | **Preprod CloudFront distribution has no WAF.** While preprod is lower risk, a WAF-free distribution can be used to probe your application logic and discover vulnerabilities before attackers test against prod. Apply the same rate limiting WAF. |
| 2 | ⚠️ Warning | **Preprod distribution has 7 origins** — likely accumulated over time. Verify all 7 are intentional and active. Unused origins are dead configuration that can cause confusion. |
| 3 | ✅ Good | Prod CloudFront uses WAF with rate limiting. |
| 4 | ✅ Good | TLSv1.2_2021 enforced on both distributions — no legacy TLS. |

---

## 9. Networking (VPC / NAT / EIP)

### 9.1 VPCs (ap-south-1)

| VPC ID | Name | CIDR | Default | Notes |
|---|---|---|---|---|
| vpc-0a87ee97a2f8757af | (default) | 172.31.0.0/16 | ✅ Yes | Unused default VPC — should be disabled |
| vpc-09233592a7b6b6677 | erpnext-vpc | 10.0.0.0/16 | No | **Primary production VPC** |
| vpc-06a24bddb8a9c6c78 | pre-prod_tenxyou-vpc | 10.0.0.0/16 | No | Pre-prod environment |
| vpc-0407f2dc23ff6886f | tenxyou-preprod-vpc | 10.0.0.0/16 | No | Duplicate preprod VPC — verify if both are needed |

### 9.2 NAT Gateways (ap-south-1)

| Gateway ID | Name | VPC | State | EIP |
|---|---|---|---|---|
| nat-1da708f051df20e72 | pre-prod_tenxyou-regional-nat | pre-prod_tenxyou-vpc | ✅ available | 13.126.24.125 |

> **Note:** Only 1 NAT Gateway found in the pre-prod VPC. No NAT Gateway found for the production VPC (`erpnext-vpc`). This means prod ECS instances and other private resources may be routing outbound traffic differently — verify.

### 9.3 Elastic IPs (ap-south-1) — 11 Total

| IP | Name / Purpose | Association | Status |
|---|---|---|---|
| 3.7.129.182 | erp-prod-EC2 | i-0b625f2bbc1955b52 | ✅ In use |
| 3.6.186.108 | strapi-prod | i-0b27df1cf9ea9691a | ✅ In use |
| 3.6.59.24 | tenxyou-intro-fe-prod | i-0fc2dc16732238cd6 | ✅ In use |
| 3.108.148.58 | saleor-dashboard | i-0f617410782147d80 | ✅ In use |
| 13.127.214.53 | (ALB managed) | ALB ENI | ✅ In use |
| 13.204.167.135 | (ALB managed) | ALB ENI | ✅ In use |
| 13.232.105.25 | (ALB managed) | ALB ENI | ✅ In use |
| 65.0.149.145 | (ALB managed) | ALB ENI | ✅ In use |
| 52.66.132.41 | (RDS managed) | RDS ENI | ✅ In use |
| 13.126.24.125 | (NAT managed) | NAT GW | ✅ In use |
| **13.204.167.190** | **saleor-prod** | **UNATTACHED** | 🔴 **IDLE — COST WASTE** |

### 9.4 Networking Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 💰 Cost | **1 unattached EIP: `13.204.167.190` (tagged "saleor-prod").** Costs ~$3.65/month (+ 18% GST = ~₹520/month). Release if no longer needed. |
| 2 | ⚠️ Warning | **Two pre-prod VPCs with identical CIDRs (10.0.0.0/16).** `pre-prod_tenxyou-vpc` and `tenxyou-preprod-vpc` have the same CIDR block. They cannot be peered with each other or with the prod VPC simultaneously. Determine which is the canonical preprod VPC. |
| 3 | ⚠️ Warning | **Default VPC exists and is unused.** The default VPC (`172.31.0.0/16`) should be deleted to prevent accidental resource launches. |
| 4 | ⚠️ Warning | **NAT Gateway only found in preprod VPC.** Confirm how prod ECS instances reach the internet for ECR image pulls — if they have public IPs, that is the path, but ECS nodes ideally should be private. |

---

## 10. DNS — Route 53

### 10.1 Hosted Zones

| Zone ID | Name | Type | Record Count | Notes |
|---|---|---|---|---|
| Z06685273N8ME5300DNLX | tenxyou.com. | Public | 58 | Primary public zone |
| Z05044523HTW8BE4ZX2UM | tenxyou-prod-internal. | Private (Cloud Map) | 2 | Service discovery — ap-south-1 |
| Z07274381HNDNUMZ4XRZW | internal-tenxyou. | Private (Cloud Map) | 2 | Service discovery — us-east-1 |

### 10.2 Route 53 Findings

| # | Severity | Finding |
|---|---|---|
| 1 | ℹ️ Info | **58 records in public zone** is a large number. A record audit to find stale/unused records pointing to decommissioned IPs is recommended. |
| 2 | ✅ Good | Private hosted zones are used for internal service discovery (Cloud Map) — good architecture. |

---

## 11. SSL/TLS Certificates (ACM)

### 11.1 ap-south-1 Certificates

| Domain | Status | Not Before | Not After | In Use | Auto-Renew Eligible |
|---|---|---|---|---|---|
| `*.tenxyou.com` | ✅ ISSUED | 2025-10-04 | **2026-11-03** | ✅ Yes | ✅ Yes |
| `tenxyou.com` | ✅ ISSUED | 2025-10-10 | **2026-11-09** | ✅ Yes | ✅ Yes |

### 11.2 us-east-1 Certificates (CloudFront)

| Domain | Status | Not Before | Not After | In Use | Auto-Renew Eligible |
|---|---|---|---|---|---|
| `tenxyou.com + *.tenxyou.com` | ✅ ISSUED | 2025-11-07 | **2026-12-07** | ✅ Yes | ✅ Yes |
| `*.tenxyou.infinitelocus.com` | ✅ ISSUED | 2026-02-03 | **2027-03-05** | ✅ Yes | ✅ Yes |

### 11.3 Certificate Findings

| # | Severity | Finding |
|---|---|---|
| 1 | ✅ Good | All 4 certificates are ISSUED and in-use with no immediate expiry risk. |
| 2 | ✅ Good | All certificates are eligible for automatic renewal (DNS-validated). |
| 3 | ℹ️ Info | Earliest expiry: `*.tenxyou.com` in ap-south-1 on **2026-11-03** — ~175 days from now. ACM auto-renews ~60 days before expiry. No action needed unless DNS validation records are removed. |

---

## 12. Security Groups Audit

### 12.1 Inbound Rules Open to 0.0.0.0/0

> **Rule:** Port 22 to 0.0.0.0/0 on anything other than the bastion is a critical security risk.

| Security Group | VPC | Open Ports to 0.0.0.0/0 | Risk Level |
|---|---|---|---|
| tenxyou-db-ec2 (sg-0a5b6c7e763745c1b) | erpnext-vpc | **22, 5432, 8000, 8080** | 🔴 Critical |
| erp-prod-sg (sg-059edd10f43193baa) | erpnext-vpc | **22**, 80, 443 | 🔴 Critical |
| saleor-sg (sg-021002d4a9eae48ca) | erpnext-vpc | **22**, 80, 443, 8000, 9000 | 🔴 Critical |
| bastion-sg (sg-0de669f7a45c47222) | erpnext-vpc | **22**, 3000 | ⚠️ Expected (bastion) — remove port 3000 |
| strapi-preprod-sg (sg-02fb52a880d22d2d8) | tenxyou-preprod-vpc | **22, 5432**, 80, 443 | 🔴 Critical |
| Saleor-preprod-dashboard-sg (sg-0f33b57ce68f0538b) | tenxyou-preprod-vpc | **22**, 80, 443, 3000, 9000 | ❌ High |
| PROD-ECS-tenxyou-SG (sg-0a316976b9ee6fbc9) | erpnext-vpc | **22** | ❌ High |
| PROD-ECS-Saleor-SG (sg-050050c90de246e19) | erpnext-vpc | **22** | ❌ High |
| ec2-db-sg (sg-0d4612108d84eaf83) | erpnext-vpc | **22** | ❌ High |
| saleor-dashboard-sg (sg-06a5a345d8ad6c8e7) | erpnext-vpc | **22**, 80, 443 | ❌ High |
| website-sg (sg-00bb80bc48d814b41) | erpnext-vpc | **22**, 80, 443 | ❌ High |
| strapi-sg (sg-0d6c3a0fa88f720db) | erpnext-vpc | **22**, 80, 443 | ❌ High |
| Nginx-sg (sg-09cc5b086da88763c) | erpnext-vpc | **22**, 80, 443 | ❌ High |
| preprod-tenxyou-fe-ec2-sg (sg-0ceaa00077ee8d422) | tenxyou-preprod-vpc | **22**, 3000 | ❌ High |
| saleor-backend-sg (sg-0359a33be7a85a0c2) | tenxyou-preprod-vpc | **22** | ⚠️ Warning |
| tenxyou-be-ecs-sg (sg-0bee1017dec609202) | tenxyou-preprod-vpc | **22**, 32782 | ⚠️ Warning |
| preprod-strapi-sg (sg-04800cd50fd31732d) | tenxyou-preprod-vpc | **22** | ⚠️ Warning |
| erp preprod sg (sg-019535459d702cdb4) | tenxyou-preprod-vpc | **22**, 80, 443 | ⚠️ Warning |
| xyz (sg-024ee2f2e66403b87) | pre-prod_tenxyou-vpc | **22** | ⚠️ Warning |
| default (sg-0428fd1bd3832e3af) | tenxyou-preprod-vpc | **22** | ⚠️ Warning |
| PROD-Tenxyou-ALB-SG (sg-047d78bc33a1ec51f) | erpnext-vpc | 80, 443 | ✅ Expected (ALB) |
| prod-tenxyou-fe-sg (sg-02dce92ac87e72996) | erpnext-vpc | 80, 443 | ✅ Expected (ALB) |

### 12.2 Security Group Findings

| # | Severity | Finding |
|---|---|---|
| 1 | 🔴 Critical | **Port 5432 (PostgreSQL) open to 0.0.0.0/0** on `tenxyou-db-ec2` and `strapi-preprod-sg`. Databases must never be reachable from the internet. |
| 2 | 🔴 Critical | **Port 22 open to 0.0.0.0/0 on production servers** including ERP, Saleor, Strapi, and ECS nodes. Production SSH access should be routed exclusively through the bastion host. Restrict all to `<bastion-sg>` as source. |
| 3 | ❌ High | **Port 8000, 8080, 9000 open to 0.0.0.0/0** — application ports exposed directly to the internet instead of being accessed via ALB/CloudFront. |
| 4 | ⚠️ Warning | **`default` security group in `tenxyou-preprod-vpc` has port 22 open.** Resources accidentally launched without a custom SG get this default and are immediately SSH-accessible. |
| 5 | ⚠️ Warning | **Bastion SG has port 3000 open to 0.0.0.0/0.** Bastion should only need port 22. Remove port 3000. |
| 6 | ℹ️ Info | The `xyz` security group name is unclear — likely test/scratch. Review and delete if unused. |

---

## 13. CloudWatch Alarms & Monitoring

### 13.1 Alarm States (ap-south-1)

| Alarm Name | State | Notes |
|---|---|---|
| ECS-PROD-Tenxyou-BE-MemoryUtilization | ✅ OK | |
| ECS-PROD-Tenxyou-FE-MemoryUtilization | ✅ OK | |
| ECS-Saleor-API-CpuUtilizationAboveDesired | ✅ OK | |
| ECS-Tenxyou-BE-RunningTasksBelowDesired | ✅ OK | |
| ECS-Tenxyou-FE-RunningTasksBelowDesired | ✅ OK | |
| TargetTracking (Saleor cluster ASG High) | ✅ OK | |
| TargetTracking (Saleor cluster ASG Low) | ✅ OK | |
| TargetTracking (Tenxyou cluster ASG High) | ✅ OK | |
| TargetTracking (Tenxyou cluster ASG Low) | ✅ OK | |
| TargetTracking PROD-Saleor-API-service High | ✅ OK | |
| TargetTracking PROD-tenxyou-be-service High | ✅ OK | |
| TargetTracking PROD-tenxyou-fe-service High | ✅ OK | |
| **ALB-Frontend-5xxxErrors** | ⚠️ **INSUFFICIENT_DATA** | Alarm exists but has no data flowing — check metric filter or ALB log configuration |
| **TargetTracking PROD-Saleor-API-service Low** | 🟡 **ALARM** | Scale-in trigger firing — Saleor API is under-utilized (expected during off-peak) |
| **TargetTracking PROD-tenxyou-be-service Low** | 🟡 **ALARM** | Scale-in trigger firing — BE under-utilized (normal) |
| **TargetTracking PROD-tenxyou-fe-service Low** | 🟡 **ALARM** | Scale-in trigger firing — FE under-utilized (normal) |

### 13.2 Monitoring Coverage Gaps

| Resource Type | Monitoring Status |
|---|---|
| EC2 Instances (all 20) | ❌ Basic only (5-min granularity) |
| RDS erp-prod-db | ✅ Performance Insights (465 days) |
| RDS erp-prod-read-replica | ✅ Enhanced Monitoring (60s) + Performance Insights |
| RDS preprod-tenxyou-saleor-db | ❌ No enhanced monitoring |
| RDS saleor-strapi-db | ❌ No enhanced monitoring, No Performance Insights |
| RDS strapi-db-read-replica | ✅ Enhanced Monitoring + Performance Insights |
| ElastiCache erp-prod-cache | ❌ No log delivery configured |
| ElastiCache saleor-prod-cache-redis | ✅ CloudWatch log delivery (engine-log, JSON) |

### 13.3 Monitoring Findings

| # | Severity | Finding |
|---|---|---|
| 1 | ❌ High | **`ALB-Frontend-5xxxErrors` alarm is in INSUFFICIENT_DATA.** The 5xx error alarm for the frontend ALB is not receiving metric data. Either the metric filter is misconfigured or ALB access logging is not flowing to CloudWatch. This means you have no alerting on production frontend errors. |
| 2 | ❌ High | **No EC2 detailed monitoring on any instance.** Basic monitoring (5-minute intervals) delays incident detection. At minimum, enable detailed monitoring on erp-prod and the bastion. |
| 3 | ⚠️ Warning | **3 scale-in alarms in ALARM state** for Saleor API, Tenxyou BE, and Tenxyou FE. These are normal auto-scaling AlarmLow triggers indicating low traffic — confirm auto-scaling is actually scaling in/out appropriately. |
| 4 | ⚠️ Warning | **`saleor-strapi-db` has no Performance Insights and no enhanced monitoring.** This is a `db.m6gd.4xlarge` with local NVMe SSD — if there are performance issues, you have no observability. |
| 5 | ✅ Good | ECS memory and CPU alarms configured for both production clusters. |
| 6 | ✅ Good | Auto-scaling target tracking configured for all 3 production ECS services. |

---

## 14. Findings Summary & Action Plan

### 14.1 Critical Issues — Fix Immediately

| # | Issue | Resource | Action |
|---|---|---|---|
| C1 | WordPress TG unhealthy | `wordpress-site` TG → `i-0fc2dc16732238cd6` | SSH to instance via bastion, check Nginx/PHP-FPM/WP, verify `/health` endpoint returns 200 |
| C2 | All 17 EBS volumes unencrypted | All ap-south-1 EC2 instances | Enable EBS encryption by default in ap-south-1; plan volume replacement via snapshot |
| C3 | Port 5432 open to 0.0.0.0/0 | `tenxyou-db-ec2` SG, `strapi-preprod-sg` | Remove 0.0.0.0/0 rules; restrict to internal SG CIDRs only |
| C4 | RDS read replica publicly accessible | `erp-prod-read-replica` | Set `PubliclyAccessible=false`; access via bastion |
| C5 | Port 22 open to 0.0.0.0/0 on prod servers | 10+ security groups | Restrict SSH to bastion SG as source on all prod SGs |
| C6 | saleor-prod-cache — no replica, no failover | `saleor-prod-cache-redis` | Add a read replica; enable automatic failover |

### 14.2 High Priority — Fix This Week

| # | Issue | Resource | Action |
|---|---|---|---|
| H1 | Zero Multi-AZ RDS | All 3 primary RDS instances | Enable Multi-AZ on `erp-prod-db` and `saleor-strapi-db` (will cause brief failover) |
| H2 | saleor-strapi-db deletion protection off | `saleor-strapi-db` | Enable deletion protection immediately |
| H3 | preprod-saleor-read-replica deletion protection off | `preprod-saleor-read-replica` | Enable deletion protection |
| H4 | ElastiCache AUTH token disabled | Both Redis clusters | Enable AUTH token; rotate into application config |
| H5 | ALB 5xx alarm INSUFFICIENT_DATA | `ALB-Frontend-5xxxErrors` | Fix metric source; verify ALB access logging is active |
| H6 | saleor-media-private-prod partial public access | S3 bucket | Audit ACL and bucket policy; enforce full block if CloudFront is origin |

### 14.3 Medium Priority — Fix Within 2 Weeks

| # | Issue | Action |
|---|---|---|
| M1 | No S3 versioning on prod media/asset buckets | Enable versioning on `saleor-media-private-prod`, `tenxyou-prod-assets`, `saleor-prod-assets` |
| M2 | No EC2 detailed monitoring | Enable detailed monitoring on all prod instances |
| M3 | EBS DeleteOnTermination=true on stateful servers | Change flag on erp-prod, wordpress-aboutus, tenxyou-db-prod volumes |
| M4 | Preprod CloudFront has no WAF | Attach rate-limiting WAF ACL to `E3VFT9H0BVWMF1` |
| M5 | Default VPC exists and unused | Delete default VPC in ap-south-1 |
| M6 | Jaeger/Mailpit in production ECS cluster | Confirm intentional; ensure no external exposure |
| M7 | Port 8000/9000 open to 0.0.0.0/0 | Restrict to ALB SG as source |

### 14.4 Low Priority / Cost Optimization

| # | Issue | Action |
|---|---|---|
| L1 | Unattached EIP `13.204.167.190` (saleor-prod) | Release if unused — saves ~₹520/month |
| L2 | Two overlapping preprod VPCs (same CIDR) | Consolidate to one preprod VPC |
| L3 | t2.xlarge instances for custom DB | Validate if t2.xlarge vs t3a.xlarge is cost-optimal; t3a is ~10% cheaper |
| L4 | Bastion SG has port 3000 open | Remove port 3000 from `bastion-sg` |
| L5 | High task definition revision numbers (fe:276) | Set up task definition deregistration lifecycle |

### 14.5 What's Working Well ✅

- All ECS services running at desired count with no pending tasks
- All production ALB target groups healthy (except WordPress)
- IMDSv2 enforced on all 20 EC2 instances
- RDS encryption at rest with KMS on all instances
- ElastiCache in-transit and at-rest encryption on both clusters
- All ACM certificates valid, auto-renew eligible
- TLSv1.2_2021 minimum enforced on CloudFront
- Prod CloudFront protected by WAF rate limiting
- Terraform state bucket correctly hardened (versioned + fully blocked)
- RDS automated snapshots current (latest: 2026-05-11)
- Private hosted zones for internal service discovery

---

## Appendix: Resource Count Summary

| Service | Count | Region |
|---|---|---|
| EC2 Instances | 17 running | ap-south-1 |
| EC2 Instances | 3 running | us-east-1 |
| ECS Clusters | 2 active | ap-south-1 |
| ECS Clusters | 1 active | us-east-1 |
| ECS Services | 6 active | both |
| ECS Running Tasks | 14 | both |
| RDS Instances | 6 | ap-south-1 |
| ElastiCache Nodes | 3 (2 groups) | ap-south-1 |
| EBS Volumes | 17 (~1,490 GB) | ap-south-1 |
| S3 Buckets | 13 | global |
| Application Load Balancers | 2 | ap-south-1 |
| Target Groups | 5 | ap-south-1 |
| CloudFront Distributions | 2 | global |
| Hosted Zones | 3 (1 public, 2 private) | global |
| ACM Certificates | 4 | ap-south-1 + us-east-1 |
| Elastic IPs | 11 (1 unattached) | ap-south-1 |
| VPCs | 4 (1 default) | ap-south-1 |
| NAT Gateways | 1 | ap-south-1 |
| CloudWatch Alarms | 16 | ap-south-1 |

---

*Generated: 2026-05-12 | Next review recommended: 2026-08-12 (quarterly)*
