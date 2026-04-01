# Networking Concepts

## 1. VPC Router Deep Dive
Network gateway Objects (transit gateway or virtual private gateway) ensure VPC traffic reaches to On-prem network.


![](../../../../Images/vpc-router.png)
- Every VPC is created with a **Main Route Table**
- **default** for every subnet in the VPC
- _custom route tables_  can be created and associated with subnets in the VPC - removing the Main RT.
- _Subnets_ are associated with One RT (Main or Custom)
- RT's can be associated with gateways.


## 2. AWS w/ Local Zones
- They are additional zone. No built in resilience.
- They are like an AZ but near your location. So lower latency.
- DX to a local zone is supported (extreme performance needs)
- Utilise parent region for control plane operations. (EBS snapshots are to parent)
- Use local zones when you need the "HIGHEST" performance.

![](../../../../Images/aws-local-zones.png)


## 3. Border Gateway Protocol (BGP)
It is a system made up of a lots of self managing network known as AS (Autonomous System). It could be a large network or a large collection of router. And it is generally controlled by one entity.

![](../../../../Images/bgp-protocol.png)

---

- `ASN (Autonomous System Number)` are unique 16-bit or 32-bit numbers allocated by IANA `(0-65535) [Public number]` vs range`(64512-65534) [Private number]`.
- Private number are used in **Private Peering** arrangement, these numbers are the identifiers of different entities within the network.
- BGP distinguish between different network using these ASN.
- BGP operates over `tcp/179` and peering is manually configured between two different autonomous systems.
- Now those `two autonomaous systems` can communicate and learn about networks from any of the peering relationships.
- Now those two ASNs can learn about networks from any of the peering relationships.
- This builds up a larger BGP network ---> Each individual AS is exchanging network topology
>Boom this is the internet from routing perspective.
- BGP is a `path-vector protocol` = Exchanges the best path to a destination between peers.
    - The path is called `_ASPATH_`
- `iBGP` = Internal BGP {Routing within an AS}
- `eBGP` = External BGP {Routing between different ASNs}

---

- All Locations or `AS` will have their their peering connection configured via table mentioned.
- When peered with another `AS` they exchange or pre-pends routes along with corresponding `ASNs`. All, possible paths to reach a destination are appended in route tables.
- We can artificially increase the length of `ASPATH` by pre-pending `ASNs` to a route. This is called **AS-Path Prepending**.

---


## How BGP Route Exchange Works

Each Autonomous System (AS) maintains a routing table. When two ASes peer (over `tcp/179`), they **exchange** their known routes along with the `ASPATH` — the ordered list of ASNs a packet must traverse to reach a destination.

---

## Example Topology

```
AS 200 ——— AS 201 ——— AS 202
  \                      /
   \                    /
    ——— AS 203 ————————
```

- **AS 200** — `120.0.0.0/16`
- **AS 201** — `50.0.0.0/16`
- **AS 202** — `80.0.0.0/16`
- **AS 203** — `100.0.0.0/16`

---

## Route Tables (per AS)

### AS 200

| Destination      | ASPATH            | Next Hop |
|------------------|-------------------|----------|
| `50.0.0.0/16`   | AS 201            | AS 201   |
| `80.0.0.0/16`   | AS 201, AS 202    | AS 201   |
| `80.0.0.0/16`   | AS 203, AS 202    | AS 203   |
| `100.0.0.0/16`  | AS 203            | AS 203   |
| `100.0.0.0/16`  | AS 201, AS 202, AS 203 | AS 201 |

> BGP selects the **shortest ASPATH** as the best path. To reach `80.0.0.0/16`, both paths have length 2 — a tiebreaker (e.g., lowest next-hop AS, MED, local pref) decides.

---

### AS 201

| Destination      | ASPATH            | Next Hop |
|------------------|-------------------|----------|
| `120.0.0.0/16`  | AS 200            | AS 200   |
| `80.0.0.0/16`   | AS 202            | AS 202   |
| `100.0.0.0/16`  | AS 202, AS 203    | AS 202   |
| `100.0.0.0/16`  | AS 200, AS 203    | AS 200   |

---

### AS 202

| Destination      | ASPATH            | Next Hop |
|------------------|-------------------|----------|
| `50.0.0.0/16`   | AS 201            | AS 201   |
| `120.0.0.0/16`  | AS 201, AS 200    | AS 201   |
| `120.0.0.0/16`  | AS 203, AS 200    | AS 203   |
| `100.0.0.0/16`  | AS 203            | AS 203   |

---

### AS 203

| Destination      | ASPATH            | Next Hop |
|------------------|-------------------|----------|
| `120.0.0.0/16`  | AS 200            | AS 200   |
| `50.0.0.0/16`   | AS 200, AS 201    | AS 200   |
| `50.0.0.0/16`   | AS 202, AS 201    | AS 202   |
| `80.0.0.0/16`   | AS 202            | AS 202   |

---

## AS-Path Prepending (Traffic Engineering)

If **AS 200** wants to discourage traffic from arriving via **AS 201**, it can **prepend its own ASN** multiple times when advertising to AS 201:

### Before Prepending (AS 202's view)

| Destination      | ASPATH            |
|------------------|-------------------|
| `120.0.0.0/16`  | AS 201, AS 200    |
| `120.0.0.0/16`  | AS 203, AS 200    |

> Both paths are length 2 — either could be selected.

### After AS 200 Prepends to AS 201

AS 200 advertises `120.0.0.0/16` to AS 201 as: `AS 200, AS 200, AS 200`

| Destination      | ASPATH                      |
|------------------|-----------------------------|
| `120.0.0.0/16`  | AS 201, AS 200, AS 200, AS 200 |
| `120.0.0.0/16`  | AS 203, AS 200              |

> Now the path via AS 203 (length 2) **wins** over the inflated AS 201 path (length 4). Traffic to `120.0.0.0/16` shifts to the AS 203 link.

---

## Key Takeaways

- BGP is a **path-vector protocol** — it selects best path based on shortest `ASPATH`.
- Every AS **pre-pends its own ASN** to routes before advertising them to peers.
- **AS-Path Prepending** artificially lengthens a path to influence inbound traffic flow.
- All possible paths are stored in the table; only the **best path** is used for forwarding.

---

## 4. AWS Global Accelerator
It starts with two `Any Cast IP Addresses` (1.2.3.4 and 4.3.2.1). It allows a single IP to be advertised from multiple locations. Routing moves traffic to closest location of `Global Accelerator Edge`. AWS has it's own internal network (fibre links) that connects it's regions.

---


![](../../../../Images/global-accelerator.png)


- When using Global accelerator, `Any Cast IP` is allocated that routes to the nearest `Global Accelerator Edge Location`.
- From that `Edge Location` traffic directly routes to the region of `Endpoint` (EC2, ALB, NLB, etc.) over AWS's private network.
- It uses `BGP` to route traffic to the nearest `Edge Location`.
- Can be used for Non HTTP/S (TCP/UDP) traffic as well.

---


## 5. IPSEC VPN Fundamentals
It is a group of protocols (exchanging keys, encrypting data, authenticating data) that are used to secure tunnels accross insecure networks between two peers (Local and Remote). It has two main phases to setup a secure VPN Connection.

![](../../../../Images/IP-sec.png)

### __Phase 1__ (**Slow and Heavy**)
---
`IKE phase 1` (Internet Key Exchange) = It is Slow and heavy, one authenticate - Pre-shared Key (password)/Certificate, using Asymmetric encryption to agree on, and create a shared Symmetric key

![](../../../../Images/ipsec-ph1.png)

- Site1 and Site2 exchanges either `Certificate or Pre-shared Key` to proving identities.
    - It's like both party agrees to be part of this VPN.
- Once Identity is confirmed ---> Now IKE phase 1
    - 1. Both parties put a random strings in their respective Routers, it is called as exchanging `PSK (pre-signed key)`. {Do not happen over network, it is manually put by Admins}
    - 2. Both parties exchange public keys over network and a DH key is generated which is identical for both Party A and Party B.
        - A x B~ = B x A~ [Both are identical using DH math]
    - 3. By now both parties have identical `DH keys`, now using DH keys + `PSK` = Hashed value.
    - 4. This hashed value is called exchange keys among each other and validates each other's identity.
    - 5. Now using DH keys + PSK = `Symmetric Key`.

---
### Phase 2
`IKE phase 2` = It is Fast and uses the keys agreed in `phase 1`. Agree encryption method, and keys used for bulk data transfer. It create IPSEC SA (Phase 2 tunnel).

![](../../../../Images/ipsec-ph2.png)

- By this time both sides have `DH Key` and `Symmetric Key`.
- Now `Symmetric Key` is used to encrypt and decrypt more __key material__ and __agreements__ between peers.
    - Idea is that one peer is informing the other about the cipher suite that one support.
    - Other peer validates and agrees on the cipher suite that it will support and chosen.
- Now both peers will use `DH Key` + `Agreed key material` = `IPSEC Key`.
- `IPSEC Key` is used for bulk encryption and decryption of interesting traffic.

---

#### Two types of VPN :- Policy based VPN and Route based VPN

![](../../../../Images/types_of_vpn.png)

1. Policy based VPNs
    - Rules set that match traffic
    - Different rules/security settings.

2. Route-based VPNs
    - Do target matching based on Prefix. (send traffic to 192.168.0.0/24 over this VPN)

---

## 6. AWS Site-to-Site VPN
A logical connection between a VPC and on-premises network encrypted using IPSEC. It is fully HA and can be provision in less than an hour.

![](../../../../Images/s2s-vpn.png)

- `VGW` = **Virtual Private Gateway** is logical gateway Object that is a target on route tables.
- `CGW` = **Customer Gateway** is a physical device or software application in your on-premises network that represents the on-premises side of the VPN connection.
- `VPN Connection` = It is a logical connection between VGW and CGW and stores configurations.

---
### STATIC vs DYNAMIC VPN
![](../../../../Images/staticVSdynamic.png)

- Speed Limitations for VPN ~ 1.25 Gbps
- Latency --> Inconsistent, depends on the path taken over internet.
- Cost --> AWS hourly cost, GB our cost, data cap (on-premises).
- Can be used as a backup for Direct Connect (DX).



## 7. Transit Gateway
It is a `Network Gateway Object` used to connect VPCs to Other networks. (VPC, Site-to-Site VPN & DX).

![](../../../../Images/transit-gateway.png)

---
![](../../../../Images/transit-gateway1.png)

- A TGW by default has one RT.
- All attachments use this RT for routing decisions.
- All attachements propagate routes to it.
- All attachements can route to all attachments.
- Upto 50 peering attachments per TGW.
- Different regions & accounts can be peered.
- No routing learning/Propagation across peer. Rather, it requires static routes.
- Data is encrypted

## 8. Advanced VPC Routing
