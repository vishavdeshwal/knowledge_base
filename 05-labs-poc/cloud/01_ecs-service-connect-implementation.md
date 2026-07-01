# ECS Service Connect — Implementation Guide

> **Goal:** Enable internal service-to-service communication between ECS services using service names instead of public domains, keeping all east-west traffic inside the VPC.

**Reference:** [04-cloud/aws/ecs.md – Internal Service-to-Service Communication](../../04-cloud/aws/ecs.md#internal-service-to-service-communication-service-connect)

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Solution Overview](#2-solution-overview)
3. [How It Works](#3-how-it-works)
4. [Implementation Steps](#4-implementation-steps)
   - [Step 1 — Create a Private Cloud Map Namespace](#step-1--create-a-private-cloud-map-namespace)
   - [Step 2 — Define Container Port in Task Definition](#step-2--define-container-port-in-task-definition)
   - [Step 3 — Enable Service Connect on ECS Service](#step-3--enable-service-connect-on-ecs-service)
   - [Step 4 — Repeat for All Backend Services](#step-4--repeat-for-all-backend-services)
   - [Step 5 — Validate](#step-5--validate)
5. [Architecture Summary](#5-architecture-summary)

---

## 1. Problem Statement

Backend services were deployed on ECS in **private subnets**, but internal service-to-service calls were being routed over **public domains** — causing unnecessary internet traversal.

![Tenxyou Service Flow](Images/tenxyou_backend_communication.png)

### What was happening

| Issue | Impact |
|-------|--------|
| Internal ECS services calling APIs via public domains | Traffic leaving the VPC unnecessarily |
| NAT gateway traversal for every internal call | Higher latency + extra data transfer costs |
| No distinction between internal and external traffic | Blurred security boundary |
| ERP and Saleor on standalone servers also exposed publicly | Increased attack surface |

### What we wanted

- Internal ECS services talk to each other via **service names**, not public URLs
- Traffic stays **inside the VPC** at all times
- External-facing APIs remain accessible as before
- Clean separation between **east-west** (internal) and **north-south** (external) traffic

---

## 2. Solution Overview

Use **ECS Service Connect**, backed by **AWS Cloud Map**, to provide internal DNS-based service discovery with stable service identities and automatic routing via Envoy proxy sidecars.

```
Before:  Service A  →  api.example.com  →  Internet (NAT)  →  Service B
After:   Service A  →  backend.internal.myapp  →  VPC (direct)  →  Service B
```

### Why ECS Service Connect over alternatives

| Option | Pros | Cons |
|--------|------|------|
| **ECS Service Connect** ✅ | Native ECS integration, Envoy sidecar, no extra infra | ECS-only |
| AWS App Mesh | Full service mesh, multi-platform | Complex setup, more overhead |
| Internal ALB | Simple, familiar | Cost, not DNS-based, no sidecar metrics |
| Direct IP discovery | No overhead | IPs change, brittle |

---

## 3. How It Works

ECS Service Connect injects an **Envoy proxy sidecar** into each task. The sidecar handles:

1. **DNS resolution** — resolves `service-name.namespace` to the correct task IP
2. **Load balancing** — distributes traffic across healthy task instances
3. **Observability** — emits connection metrics automatically to CloudWatch

```
┌─────────────────────────────────────────────────────┐
│                    VPC (private subnet)              │
│                                                      │
│  ┌──────────────┐        ┌──────────────────────┐   │
│  │   Service A  │        │      Service B        │   │
│  │  ┌────────┐  │        │  ┌──────────────────┐ │   │
│  │  │  App   │  │        │  │       App        │ │   │
│  │  └───┬────┘  │        │  └────────┬─────────┘ │   │
│  │  ┌───▼────┐  │        │  ┌────────▼─────────┐ │   │
│  │  │ Envoy  │──┼────────┼─▶│      Envoy       │ │   │
│  │  └────────┘  │        │  └──────────────────┘ │   │
│  └──────────────┘        └──────────────────────┘   │
│                                                      │
│         DNS: backend.internal.myapp                  │
│         Resolved via AWS Cloud Map                   │
└─────────────────────────────────────────────────────┘
```

---

## 4. Implementation Steps

### Step 1 — Create a Private Cloud Map Namespace

**Console path:**
> AWS Console → Cloud Map → Namespaces → Create namespace

#### Configuration

| Field | Value |
|-------|-------|
| Namespace type | **Private DNS** |
| Namespace name | `internal.myapp` |
| VPC | Same VPC as ECS cluster |

#### What this does

- Defines the **DNS boundary** for internal service discovery
- All Service Connect services in this cluster will use this as their DNS suffix
- No services or DNS records exist at this point — just the namespace

> ⚠️ **Important:** The namespace must be in the same VPC as your ECS cluster. Using a different VPC will result in DNS resolution failures.

---

### Step 2 — Define Container Port in Task Definition

**Console path:**
> ECS → Task Definitions → [Your Task] → Container → Port Mappings

#### What to configure

- Set the port your application listens on (e.g. `8080`)
- ECS will automatically generate a **port alias** from this

```
Container port : 8080
Port alias     : backend-8080-tcp   ← auto-generated, used in Step 3
```

> 💡 The port alias is just a label — it becomes the reference handle for Service Connect configuration in the next step. No DNS or discovery happens here yet.

---

### Step 3 — Enable Service Connect on ECS Service

**Console path:**
> ECS → Cluster → [Your Service] → Update Service → Service Connect

This is the **core configuration step** where the service gets its internal identity.

---

#### 3.1 — Enable Service Connect

Check **Use Service Connect** and select the mode:

| Mode | What it means | Use when |
|------|--------------|----------|
| **Client only** | Can call other services, but cannot be discovered | Pure consumers (e.g. cron jobs) |
| **Client and server** ✅ | Can call others AND be discovered by others | Most backend services |

> We used **Client and server** for all backend services so they can both call and be called.

---

#### 3.2 — Select Namespace

Select the Cloud Map namespace created in Step 1:

```
Namespace: internal.myapp
```

This becomes the **DNS suffix** for all Service Connect services in this cluster. Every service registered here will be reachable at `<discovery-name>.internal.myapp`.

---

#### 3.3 — Configure the Service Connect Endpoint

Click **Add port mappings and applications** and fill in:

![Service Connect Configuration](Images/service_connect.png)

| Field | Value | Notes |
|-------|-------|-------|
| Port alias | `backend-8080-tcp` | Must match the alias from Task Definition |
| Discovery name | `backend` | Logical name — this becomes the DNS hostname |
| DNS | `backend.internal.myapp` | Auto-derived by ECS from discovery name + namespace |
| Port | `8080` | The port your app actually listens on |

#### How the DNS resolves

```
Discovery name  +  Namespace       =  Internal DNS
backend         +  internal.myapp  =  backend.internal.myapp
```

Other services call this service using:
```bash
http://backend.internal.myapp:8080/api/endpoint
```

No public domain. No NAT. Stays inside the VPC.

---

### Step 4 — Repeat for All Backend Services

Enable Service Connect on every ECS service that needs to be reachable internally:

- Use the **same namespace** (`internal.myapp`) for all services
- Assign **unique discovery names** per service

Example naming:

| Service | Discovery Name | Internal DNS |
|---------|---------------|--------------|
| Django backend | `django-api` | `django-api.internal.myapp` |
| FastAPI service | `fastapi` | `fastapi.internal.myapp` |
| Worker service | `worker` | `worker.internal.myapp` |

> ⚠️ Discovery names must be unique within a namespace. Duplicate names will cause Service Connect to fail silently.

---

### Step 5 — Validate

Once services are deployed, exec into a running task and test DNS resolution:

```bash
# Check if the service DNS resolves
nslookup backend.internal.myapp

# Curl the service directly using the internal DNS
curl http://backend.internal.myapp:8080/health

# From within the same task, short names also work
curl http://backend:8080/health
```

#### Expected output from nslookup

```
Server:    10.0.0.2
Address:   10.0.0.2#53

Name:      backend.internal.myapp
Address:   10.1.x.x    ← private IP of the ECS task
```

If DNS does not resolve, check:
- Both services are in the same Cloud Map namespace
- Service Connect is enabled with **Client and server** mode (not Client only)
- The ECS service has finished deploying (new tasks with Envoy sidecar are running)
- Security groups allow traffic on the configured port between services

---

## 5. Architecture Summary

| Component | Role |
|-----------|------|
| **AWS Cloud Map** | Namespace registry — defines the DNS zone (`internal.myapp`) |
| **ECS Service Connect** | Registers services into Cloud Map, manages Envoy sidecars |
| **Envoy Proxy (sidecar)** | Intercepts traffic, handles routing, emits metrics |
| **Private DNS** | Resolves `service.namespace` to task private IPs within VPC |

### Traffic flow (after implementation)

```
Service A Task
  └─ App calls http://backend.internal.myapp:8080
       └─ Envoy sidecar intercepts
            └─ Resolves via Cloud Map DNS
                 └─ Routes to Service B Task (private IP, same VPC)
                      └─ Service B Envoy receives
                           └─ Forwards to Service B App container
```

No internet. No NAT. No public DNS lookup.

---

> **Related Docs:**
> - [AWS ECS Service Connect — Official Docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
> - [AWS Cloud Map — Namespaces](https://docs.aws.amazon.com/cloud-map/latest/dg/working-with-namespaces.html)
> - [04-cloud/aws/ecs.md](../../04-cloud/aws/ecs.md)