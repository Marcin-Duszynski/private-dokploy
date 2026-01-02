# Dokploy Infrastructure Security Changes Report

**Date:** 2026-01-02
**Environment:** Oracle Cloud Infrastructure (OCI) - Frankfurt Region (eu-frankfurt-1)
**Compartment OCID:** `ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q`
**Resource Manager Stack:** `dokploy` (Terraform 1.5.x)
**Stack OCID:** `ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q`

**Servers:**
| Name | Public IP | Private IP | AD |
|------|-----------|------------|-----|
| dokploy-main-cli7h | 141.147.10.90 | 10.0.0.253 | EU-FRANKFURT-1-AD-1 |
| dokploy-worker-1-cli7h | 130.61.113.138 | 10.0.0.107 | EU-FRANKFURT-1-AD-2 |
| dokploy-worker-2-cli7h | 130.61.47.55 | 10.0.0.44 | EU-FRANKFURT-1-AD-2 |

**Network:**
- **VCN:** `network-dokploy-cli7h` (10.0.0.0/16)
- **VCN OCID:** `ocid1.vcn.oc1.eu-frankfurt-1.amaaaaaajby5j4aaln53uql7gqg4gdhzduql4upntlfmnhistwp3rhsbwafq`
- **Subnet:** 10.0.0.0/24

---

## Summary

This report documents infrastructure setup and security hardening changes made to the Dokploy deployment on Oracle Cloud Infrastructure.

---

## 1. Initial Issues Resolved

### 1.1 Port 3000 Not Reachable
- **Problem:** Dokploy UI on port 3000 was not accessible from the internet
- **Root Cause:** Docker and Dokploy were not installed; iptables was blocking port 3000
- **Solution:**
  - Installed Docker and Dokploy on main server
  - Added iptables rule for port 3000

### 1.2 Docker Permission Denied on Remote Servers
- **Problem:** `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`
- **Root Cause:**
  - Workers needed to be standalone swarm managers (not workers in main swarm)
  - Missing Dokploy requirements (nixpacks, rclone, buildpacks, railpack)
  - Dokploy server username was not set to `root`
- **Solution:**
  - Configured each server as standalone Docker Swarm manager
  - Installed all required tools
  - Created `/etc/dokploy` directory and `dokploy-network`

---

## 2. Security Vulnerabilities Identified

| Risk Level | Issue | Description |
|------------|-------|-------------|
| High | curl \| sh pattern | Scripts downloaded and executed without integrity verification |
| High | PermitRootLogin yes | Root SSH allowed password authentication |
| High | Swarm token exposed | Join token visible in terminal output |
| Medium | Swarm ports open to internet | Ports 2376, 2377, 4789, 7946 exposed to 0.0.0.0/0 |
| Medium | Port 3000 public | Dokploy UI exposed without HTTPS |

---

## 3. Security Fixes Applied

### 3.1 SSH Hardening

**All three servers** - Changed root login from password to key-only:

```bash
# Before
PermitRootLogin yes

# After
PermitRootLogin prohibit-password
```

**Command executed:**
```bash
sed -i 's/PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart sshd
```

### 3.2 Docker Swarm Token Rotation

**Main server (141.147.10.90):**
```bash
docker swarm join-token --rotate worker
```
- Old token invalidated
- New token generated

### 3.3 OCI Security List Update

**Security List:** `Dokploy Security List`
**OCID:** `ocid1.securitylist.oc1.eu-frankfurt-1.aaaaaaaaxrysa2fthssid2fh3yv7v74363r6a3eh7w2qm6vesmvepuxbos2q`

#### Ports Restricted to VCN Only (10.0.0.0/16):

| Port | Protocol | Service | Before | After |
|------|----------|---------|--------|-------|
| 2376 | TCP | Docker Swarm | 0.0.0.0/0 | 10.0.0.0/16 |
| 2377 | TCP | Swarm Management | 0.0.0.0/0 | 10.0.0.0/16 |
| 4789 | UDP | Swarm Overlay | 0.0.0.0/0 | 10.0.0.0/16 |
| 7946 | TCP/UDP | Swarm Node Comm | 0.0.0.0/0 | 10.0.0.0/16 |
| 3000 | TCP | Dokploy UI | 0.0.0.0/0 | 10.0.0.0/16 |

#### Ports Remaining Public (0.0.0.0/0):

| Port | Protocol | Service | Justification |
|------|----------|---------|---------------|
| 22 | TCP | SSH | Remote management (key-only) |
| 80 | TCP | HTTP | Web traffic |
| 443 | TCP | HTTPS | Web traffic |
| 81 | TCP | Traefik HTTP | Reverse proxy |
| 444 | TCP | Traefik HTTPS | Reverse proxy |

---

## 4. Files Modified

### 4.1 network.tf

Changed Docker Swarm and Dokploy ingress rules from `0.0.0.0/0` to `10.0.0.0/16`:

```hcl
# Before
source = "0.0.0.0/0"

# After
source = "10.0.0.0/16"
```

Affected rules:
- Port 3000 (Dokploy)
- Port 2376 (Docker Swarm)
- Port 2377 (Swarm Management)
- Port 7946 TCP/UDP (Swarm Node Communication)
- Port 4789 (Swarm Overlay Network)

### 4.2 bin/dokploy-main.sh

1. Changed SSH root login to key-only:
```bash
# Before
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/'

# After
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/'
```

2. Added missing iptables rules:
```bash
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 3000 -j ACCEPT
```

### 4.3 bin/dokploy-worker.sh

1. Changed SSH root login to key-only (same as main)
2. Added missing iptables rules for ports 80, 443

---

## 5. Tools Installed on Workers

Both worker servers (130.61.113.138 and 130.61.47.55):

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 29.1.3 | Container runtime |
| RClone | 1.72.1 | Backup operations |
| Nixpacks | 1.41.0 | Application builds |
| Buildpacks (pack) | 0.39.1 | Alternative build system |
| Railpack | 0.15.4 | Build tool support |

---

## 6. OCI CLI Setup

Installed and configured OCI CLI for infrastructure management:

```bash
brew install oci-cli  # Version 3.71.4
oci setup config      # Interactive configuration
```

Configuration file: `~/.oci/config`

---

## 7. Recommendations for Future

1. **Verify downloaded scripts** - Download install scripts first, verify checksums, then execute
2. **Use OCI Resource Manager for changes** - Deploy via Resource Manager to ensure infrastructure matches code
3. **Consider Network Security Groups** - Oracle recommends NSGs over Security Lists for granular control
4. **Set up HTTPS for Dokploy** - Configure Traefik with TLS certificates
5. **Restrict SSH access** - Consider limiting SSH to specific IP ranges or VPN

---

## 8. Commands Reference

### Rotate Swarm Token
```bash
ssh -i ~/.ssh/oci_instance root@141.147.10.90 "docker swarm join-token --rotate worker"
```

### Update Security List via OCI CLI
```bash
oci network security-list update \
  --security-list-id "<OCID>" \
  --ingress-security-rules file:///path/to/rules.json \
  --force
```

### Check Security List Rules
```bash
oci network security-list get --security-list-id "<OCID>" | jq '.data."ingress-security-rules"'
```

---

## Appendix: Server Final State

### Docker Swarm Status
```
ID                            HOSTNAME                 STATUS    MANAGER STATUS
jd890yt062go66alo7zl32h57 *   dokploy-main-cli7h       Ready     Leader
```

Note: Workers are now standalone swarm managers (not part of main cluster) as required by Dokploy for remote server deployment.
