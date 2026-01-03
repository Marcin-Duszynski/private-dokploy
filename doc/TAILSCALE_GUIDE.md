# Tailscale VPN Guide

This guide explains how to configure Tailscale VPN for secure access to your Dokploy infrastructure on OCI.

Based on official Tailscale documentation: https://tailscale.com/kb/1149/cloud-oracle

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

## OCI-Specific Requirements

### UDP Port 41641 (Required for Direct Connections)

For optimal performance with direct peer-to-peer connections (instead of relayed via DERP), you must add a **stateless** UDP ingress rule to the OCI Security List.

**Via OCI Console:**

1. Go to **Networking > Virtual Cloud Networks > [Your VCN] > Security Lists**
2. Click on the security list (e.g., `Dokploy Security List`)
3. Click **Add Ingress Rules**
4. Configure:
   - **Stateless**: Yes (IMPORTANT - must be stateless)
   - **Source CIDR**: `0.0.0.0/0`
   - **IP Protocol**: UDP
   - **Destination Port Range**: `41641`
   - **Description**: `Tailscale direct connections (stateless)`

**Why stateless?** Tailscale uses this port to detect NAT port mappings. Stateless rules allow the bidirectional UDP traffic needed for direct connections.

**Without this rule:** Tailscale will still work but will relay traffic through DERP servers, resulting in higher latency.

### DNS Considerations

The current Terraform scripts use `--accept-dns=true` which enables Tailscale's MagicDNS (allowing `ssh ubuntu@dokploy-main` to work).

**Trade-off:**

| Setting | MagicDNS | Oracle VCN DNS | Recommendation |
|---------|----------|----------------|----------------|
| `--accept-dns=true` | Works | May break | Good for simple setups |
| `--accept-dns=false` | Needs config | Works | Better for VCN-heavy use |

**Official Tailscale recommendation:** Use `--accept-dns=false` and configure split DNS in the Tailscale admin console. This preserves:

- VCN hostnames (`.oraclevcn.com`) resolution
- Oracle metadata service (169.254.169.254) access
- Internal VCN communication

To change this, modify the scripts in `bin/dokploy-main.sh` and `bin/dokploy-worker.sh`:
```bash
# Change from:
tailscale up ... --accept-dns=true ...

# To:
tailscale up ... --accept-dns=false ...
```

Then configure split DNS (see [DNS Configuration](#dns-configuration-optional) below).

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

### Tailscale API Key (Local Environment)

The `TAILSCALE_API_KEY` environment variable is configured in `~/.zshrc` for local Tailscale CLI operations and API access.

```bash
# Verify it's set
echo $TAILSCALE_API_KEY
```

Generate API keys at: https://login.tailscale.com/admin/settings/keys (select "API access token")

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

### Remove Public SSH Access (Recommended)

Once Tailscale is confirmed working, the official Tailscale guide recommends removing the SSH ingress rule from the OCI Security List entirely. SSH access will then only be possible via Tailscale.

**Steps:**

1. Verify Tailscale SSH works: `tailscale ssh ubuntu@dokploy-main`
2. Go to **Networking > Virtual Cloud Networks > Security Lists**
3. Remove or restrict the SSH (port 22) ingress rule
4. Optionally, update Terraform:
   ```hcl
   ssh_allowed_cidr = "100.64.0.0/10"  # Tailscale CGNAT range only
   ```

This ensures instances are only accessible via the encrypted Tailscale network.

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

## Route Advertisement (Optional)

To access other VCN resources through your Tailscale network, you can configure one instance as a subnet router.

### Enable Subnet Router on Main Instance

SSH into the main instance and run:

```bash
# Advertise VCN subnet and Oracle metadata service
sudo tailscale set --advertise-routes=10.0.0.0/24,169.254.169.254/32
```

### Approve Routes in Admin Console

1. Go to https://login.tailscale.com/admin/machines
2. Click on `dokploy-main`
3. Under **Subnets**, approve the advertised routes

### Enable IP Forwarding (if not already enabled)

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Now devices on your Tailscale network can access VCN resources directly.

## DNS Configuration (Optional)

To resolve Oracle VCN hostnames (`.oraclevcn.com`) from any device on your Tailscale network:

### Configure Split DNS in Tailscale Admin

1. Go to https://login.tailscale.com/admin/dns
2. Under **Nameservers**, click **Add nameserver**
3. Configure:
   - **Nameserver**: The Tailscale IP of your dokploy-main instance (e.g., `100.x.x.x`)
   - **Restrict to domain**: `oraclevcn.com`

This routes DNS queries for `.oraclevcn.com` to your OCI instance, which can resolve internal VCN hostnames.

### Alternative: Use Oracle DNS Directly

If you've set up route advertisement (above), you can point to Oracle's metadata DNS:

1. **Nameserver**: `169.254.169.254`
2. **Restrict to domain**: `oraclevcn.com`

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

### Verify Direct Connections (Not Relayed)

Check if traffic is going direct or via DERP relay:

```bash
# From your local machine
tailscale ping dokploy-main
```

**Good output (direct):**
```
pong from dokploy-main (100.x.x.x) via 141.147.10.90:41641 in 15ms
```

**Relayed output (needs UDP 41641 rule):**
```
pong from dokploy-main (100.x.x.x) via DERP(fra) in 45ms
```

If you see `via DERP`, add the stateless UDP 41641 ingress rule to your OCI Security List (see [OCI-Specific Requirements](#oci-specific-requirements)).

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
          │           UDP 41641 (direct)          │
          │            ┌──────┴──────┐            │
          │            │  OCI VCN    │            │
          │            │ 10.0.0.0/16 │            │
          │            └─────────────┘            │
          │                                       │
          └───────────────────────────────────────┘
                    Encrypted WireGuard tunnel

Required OCI Security List Rules:
┌────────────┬──────────┬─────────────┬───────────┐
│ Protocol   │ Port     │ Source      │ Stateless │
├────────────┼──────────┼─────────────┼───────────┤
│ UDP        │ 41641    │ 0.0.0.0/0   │ Yes       │
└────────────┴──────────┴─────────────┴───────────┘
```

## Tailscale vs OCI Bastion

| Feature | Tailscale | OCI Bastion |
|---------|-----------|-------------|
| **Setup** | Auth key + UDP 41641 rule | Session creation per connection |
| **Session duration** | Unlimited | Max 3 hours |
| **Cost** | Free (up to 100 devices) | Free |
| **SSH keys** | Optional (Tailscale SSH) | Required |
| **Direct access** | Yes (with UDP 41641) | Proxy only |
| **MagicDNS** | Yes | No |
| **Works offline** | Cached connections | Requires OCI API |
| **OCI config needed** | Stateless UDP 41641 ingress | None (managed service) |

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
