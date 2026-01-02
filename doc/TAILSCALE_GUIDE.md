# Tailscale VPN Guide

This guide explains how to configure Tailscale VPN for secure access to your Dokploy infrastructure on OCI.

## Overview

Tailscale creates a secure mesh VPN network between your devices. Once configured, you can access your OCI instances using:

- **Tailscale hostnames**: `ssh ubuntu@dokploy-main`
- **Tailscale IPs**: `ssh ubuntu@100.x.x.x`
- **Tailscale SSH**: Browser-based SSH without managing keys

### Benefits

| Feature | Description |
|---------|-------------|
| **No public SSH** | Instances accessible only via Tailscale network |
| **MagicDNS** | Access by hostname instead of IP |
| **Tailscale SSH** | SSH without managing keys, with session recording |
| **ACLs** | Fine-grained access control per user/device |
| **Free tier** | Up to 100 devices, 3 users |

## Prerequisites

1. A Tailscale account (https://tailscale.com)
2. Tailscale installed on your local machine
3. A Tailscale auth key

## Step 1: Generate Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click **Generate auth key**
3. Configure the key:
   - **Reusable**: Yes (required for multiple instances)
   - **Expiration**: Set as needed (or no expiry)
   - **Ephemeral**: Optional - devices auto-removed when offline for 30+ days
   - **Tags**: Optional - for ACL-based access control
4. Copy the generated key (starts with `tskey-auth-`)

## Step 2: Configure Terraform Variables

### Option A: OCI Resource Manager (Recommended)

1. Go to your Resource Manager stack in OCI Console
2. Click **Edit** > **Edit variables**
3. Set:
   - `enable_tailscale` = `true`
   - `tailscale_auth_key` = `tskey-auth-xxxxx...`
4. Save and run a Plan/Apply job

### Option B: terraform.tfvars (Local)

```hcl
enable_tailscale   = true
tailscale_auth_key = "tskey-auth-xxxxx..."
```

### Option C: Environment Variable

```bash
export TF_VAR_tailscale_auth_key="tskey-auth-xxxxx..."
```

## Step 3: Deploy

After setting variables, deploy the infrastructure:

```bash
# Create plan
oci resource-manager job create-plan-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q

# Apply
oci resource-manager job create-apply-job \
  --stack-id ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaajby5j4aardmmfasvevp7yblazeducumqsa626n5ue4jcqv2zek6q \
  --execution-plan-strategy FROM_LATEST_PLAN_JOB
```

## Step 4: Verify Devices

After deployment, verify devices appeared in Tailscale:

1. Go to https://login.tailscale.com/admin/machines
2. You should see:
   - `dokploy-main`
   - `dokploy-worker-1`
   - `dokploy-worker-2` (if configured)
   - etc.

Or via CLI:

```bash
tailscale status
```

## Connecting to Instances

### SSH via Tailscale Hostname (MagicDNS)

```bash
# Main instance
ssh ubuntu@dokploy-main

# Worker instances
ssh ubuntu@dokploy-worker-1
ssh ubuntu@dokploy-worker-2
```

### SSH via Tailscale IP

```bash
# Find the Tailscale IP
tailscale status | grep dokploy

# Connect
ssh ubuntu@100.x.x.x
```

### Tailscale SSH (Browser-based)

1. Go to https://login.tailscale.com/admin/machines
2. Click on the machine
3. Click **SSH** button

Or via CLI:

```bash
# Uses Tailscale's SSH (no local keys needed)
tailscale ssh ubuntu@dokploy-main
```

## Accessing Dokploy UI

With Tailscale, you can access the Dokploy UI directly on port 3000 (normally VCN-restricted):

```
http://dokploy-main:3000
```

Or via Tailscale IP:

```
http://100.x.x.x:3000
```

## Security Recommendations

### Disable Public SSH (Optional)

If using Tailscale exclusively, you can disable public SSH by setting:

```hcl
ssh_allowed_cidr = "100.64.0.0/10"  # Tailscale CGNAT range only
```

This restricts SSH to Tailscale network only.

### Enable ACLs

For team environments, configure Tailscale ACLs to control who can access which machines:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:devops"],
      "dst": ["tag:dokploy:*"]
    }
  ],
  "tagOwners": {
    "tag:dokploy": ["group:devops"]
  }
}
```

Then generate auth keys with `--tags=tag:dokploy`.

### Enable Key Expiry

For better security, use auth keys with expiration and enable key expiry for machines in Tailscale admin.

## Troubleshooting

### Check Tailscale Status on Instance

```bash
# SSH in via bastion or public IP first
ssh ubuntu@<public-ip>

# Check Tailscale status
sudo tailscale status

# Check if Tailscale is running
sudo systemctl status tailscaled

# View Tailscale logs
sudo journalctl -u tailscaled -f
```

### Re-authenticate Device

If a device loses authentication:

```bash
# On the instance
sudo tailscale up --authkey="tskey-auth-xxxxx..." --ssh --accept-routes --accept-dns=true
```

### Device Not Appearing

1. Check cloud-init logs:
   ```bash
   sudo cat /var/log/cloud-init-output.log | grep -i tailscale
   ```

2. Verify auth key is valid and not expired

3. Manually install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --authkey="tskey-auth-xxxxx..." --ssh --hostname="dokploy-main"
   ```

### Firewall Issues

Tailscale should work through NAT without additional firewall rules. If having connection issues:

```bash
# Check UFW status
sudo ufw status

# Verify Tailscale rules exist
sudo ufw status | grep -i tailscale

# Check iptables
sudo iptables -L -n | grep 41641
```

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Tailscale Network                           │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ Your Laptop  │    │ dokploy-main │    │dokploy-worker│      │
│  │ 100.x.x.1    │◄──►│ 100.x.x.2    │◄──►│ 100.x.x.3    │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                   │               │
└─────────┼───────────────────┼───────────────────┼───────────────┘
          │                   │                   │
          │            ┌──────┴──────┐            │
          │            │  OCI VCN    │            │
          │            │ 10.0.0.0/16 │            │
          │            └─────────────┘            │
          │                                       │
          └───────────────────────────────────────┘
                    Encrypted WireGuard tunnel
```

## Tailscale vs OCI Bastion

| Feature | Tailscale | OCI Bastion |
|---------|-----------|-------------|
| **Setup** | Auth key only | Session creation per connection |
| **Session duration** | Unlimited | Max 3 hours |
| **Cost** | Free (up to 100 devices) | Free |
| **SSH keys** | Optional (Tailscale SSH) | Required |
| **Direct access** | Yes | Proxy only |
| **MagicDNS** | Yes | No |
| **Works offline** | Cached connections | Requires OCI API |

Both can be used together - Tailscale for daily access, Bastion as backup.

## Quick Reference

```bash
# Check Tailscale status
tailscale status

# List all machines
tailscale status --json | jq '.Peer | keys'

# SSH to main instance
ssh ubuntu@dokploy-main

# SSH using Tailscale SSH
tailscale ssh ubuntu@dokploy-main

# Access Dokploy UI
open http://dokploy-main:3000

# Ping test
tailscale ping dokploy-main
```
