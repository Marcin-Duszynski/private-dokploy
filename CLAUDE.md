# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-Code project deploying Dokploy (open-source deployment platform) on Oracle Cloud Infrastructure (OCI) Free Tier using Terraform. Creates a Docker Swarm cluster with one main instance and configurable worker nodes.

## Commands

All infrastructure changes are deployed via OCI Resource Manager. See [Deploying Terraform Changes via OCI Resource Manager](#deploying-terraform-changes-via-oci-resource-manager) for detailed steps.

```bash
# Preview changes (plan)
oci resource-manager job create-plan-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q

# Apply infrastructure
oci resource-manager job create-apply-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q \
  --execution-plan-strategy FROM_LATEST_PLAN_JOB

# Destroy all resources
oci resource-manager job create-destroy-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q \
  --execution-plan-strategy AUTO_APPROVED

# View job logs
oci resource-manager job get-job-logs --job-id <job-ocid>

# Local validation (before uploading)
terraform validate
terraform fmt
```

## Architecture

### Network Topology
```
VCN: 10.0.0.0/16
  └── Subnet: 10.0.0.0/24
        ├── dokploy-main (public IP, runs Dokploy + Docker Swarm manager)
        └── dokploy-worker-N (public IPs, Docker Swarm workers)
```

### File Structure
- `main.tf` - OCI compute instances (main + workers)
- `network.tf` - VCN, subnet, internet gateway, security list rules
- `variables.tf` - Input variables with defaults
- `locals.tf` - Shared instance configuration
- `output.tf` - Dashboard URL and worker IPs
- `bin/dokploy-main.sh` - Main instance user_data script (Docker + Dokploy install)
- `bin/dokploy-worker.sh` - Worker instance user_data script (SSH + firewall setup)

### Port Exposure
**Public (0.0.0.0/0):** 22 (SSH), 80/443 (HTTP/S), 81/444 (Traefik)
**VCN only (10.0.0.0/16):** 3000 (Dokploy UI), 2376/2377 (Docker Swarm), 7946/4789 (Swarm overlay)

### Instance Configuration
- Shape: VM.Standard.A1.Flex (free tier)
- OS: Ubuntu 22.04
- Default: 6GB RAM, 1 OCPU per instance
- Max 4 instances total (1 main + 3 workers) on free tier

## Required Variables

```hcl
ssh_authorized_keys         # SSH public key
compartment_id              # OCI compartment OCID
source_image_id             # Ubuntu 22.04 image OCID for region
availability_domain_main    # AD for main instance
availability_domain_workers # AD for worker instances
```

## Security Notes

- SSH uses key-only authentication (PermitRootLogin prohibit-password)
- Docker Swarm ports restricted to VCN (not internet-exposed)
- Legacy IMDS endpoints disabled
- PV encryption in transit enabled
- Dokploy UI (port 3000) accessible only within VCN; use Traefik for public access

## Current OCI Deployment

**Region:** eu-frankfurt-1
**Resource Manager Stack:** `dokploy` (Terraform 1.5.x, ACTIVE)
**Stack OCID:** `ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q`

### Network
- **VCN:** `network-dokploy-cli7h` (10.0.0.0/16)
- **Subnet:** 10.0.0.0/24

### Instances
| Name | Public IP | Private IP | AD |
|------|-----------|------------|-----|
| dokploy-main-cli7h | 141.147.10.90 | 10.0.0.253 | EU-FRANKFURT-1-AD-1 |
| dokploy-worker-1-cli7h | 130.61.113.138 | 10.0.0.107 | EU-FRANKFURT-1-AD-2 |
| dokploy-worker-2-cli7h | 130.61.47.55 | 10.0.0.44 | EU-FRANKFURT-1-AD-2 |

### OCI CLI Commands
```bash
# List Resource Manager stacks
oci resource-manager stack list --compartment-id ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q --all

# View stack details
oci resource-manager stack get --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q

# List compute instances
oci compute instance list --compartment-id ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q --all --output table

# List instance IPs
oci compute instance list-vnics --compartment-id ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q --all --output table
```

## Deploying Terraform Changes via OCI Resource Manager

### Step 1: Update Stack Configuration (if code changed)

```bash
# Create a zip of the repo (excluding non-Terraform files)
cd /Users/marcind/Desktop/Projects/Private/Infrastructure/private-dokploy
zip -r ../dokploy-update.zip . -x "*.git*" -x ".claude/*" -x ".planning/*" -x "doc/*"

# Upload new code to the stack
oci resource-manager stack update \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q \
  --config-source ../dokploy-update.zip
```

### Step 2: Run Plan Job (`terraform plan`)

```bash
oci resource-manager job create-plan-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q
```

Check plan output:
```bash
# Get job status
oci resource-manager job get --job-id <job-ocid>

# View plan logs
oci resource-manager job get-job-logs --job-id <job-ocid>
```

### Step 3: Run Apply Job (`terraform apply`)

```bash
# Apply using the latest plan
oci resource-manager job create-apply-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q \
  --execution-plan-strategy FROM_LATEST_PLAN_JOB

# Or auto-approve (skip plan review)
oci resource-manager job create-apply-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q \
  --execution-plan-strategy AUTO_APPROVED
```

### Command Reference

| Terraform | OCI Resource Manager |
|-----------|---------------------|
| `terraform plan` | `oci resource-manager job create-plan-job --stack-id <ocid>` |
| `terraform apply` | `oci resource-manager job create-apply-job --stack-id <ocid>` |
| `terraform destroy` | `oci resource-manager job create-destroy-job --stack-id <ocid>` |
