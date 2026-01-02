# OCI Security Hardening Roadmap

## Milestone: v1.0 - Security Hardened Infrastructure

### Phase 01: Security Hardening
**Scope:** Apply all critical and high-priority security fixes to Terraform and shell scripts

| Plan | Focus | Status |
|------|-------|--------|
| 01-01 | Terraform: IMDSv2 + OCI Agent Plugins | pending |
| 01-02 | Terraform: Network Security (SSH restriction, NSG) | pending |
| 01-03 | Scripts: SSH Hardening | pending |
| 01-04 | Scripts: Host Firewall + Docker Hardening | pending |

**Verification:** `terraform validate` passes locally, then run plan job via OCI Resource Manager
