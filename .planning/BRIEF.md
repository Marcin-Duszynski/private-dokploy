# OCI Security Hardening Brief

## Vision
Harden the Dokploy OCI infrastructure to meet December 2025 security best practices, protecting against common attack vectors whilst maintaining free tier compatibility.

## Current State
- Dokploy deployment on OCI Free Tier (1 main + configurable workers)
- Docker Swarm cluster with Traefik reverse proxy
- Basic security in place but with significant gaps

## Critical Gaps Identified
1. **IMDSv1 enabled** - Legacy metadata service vulnerable to SSRF attacks
2. **SSH open to internet** - Port 22 accessible from 0.0.0.0/0
3. **Vulnerability Scanning disabled** - OCI agent plugin not active
4. **SSH not hardened** - Password auth not disabled, root login permitted
5. **UFW not enabled** - Firewall rules exist but UFW service not started
6. **Docker not hardened** - Default installation without security options
7. **Port 3000 exposed** - Dokploy UI accessible via iptables bypass

## Success Criteria
- IMDSv2 enforced (legacy disabled)
- SSH restricted to VCN or specified CIDR
- All OCI security plugins enabled
- SSH hardened (key-only, no root, rate limiting)
- Host firewall enabled and configured
- Docker hardened with best practices
- All Swarm traffic encrypted within VCN
