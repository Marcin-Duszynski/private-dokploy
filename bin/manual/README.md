# Manual Setup Scripts

Scripts for manual configuration of instances via SSH.
Based on: https://tailscale.com/kb/1149/cloud-oracle

## Tailscale VPN Setup

### Prerequisites

1. Generate an auth key at https://login.tailscale.com/admin/settings/keys
   - Enable "Reusable" for multiple instances
   - Set appropriate expiry

2. Ensure `enable_tailscale = true` in OCI Resource Manager stack (adds UDP 41641 security rule)

### Installation

Copy the script to each instance and run:

```bash
# Set your auth key
export TAILSCALE_AUTH_KEY='tskey-auth-xxx...'

# Main instance
scp bin/manual/setup-tailscale.sh ubuntu@141.147.10.90:/tmp/
ssh ubuntu@141.147.10.90 "sudo TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' HOSTNAME='dokploy-main' bash /tmp/setup-tailscale.sh"

# Worker 1
scp bin/manual/setup-tailscale.sh ubuntu@130.61.113.138:/tmp/
ssh ubuntu@130.61.113.138 "sudo TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' HOSTNAME='dokploy-worker-1' bash /tmp/setup-tailscale.sh"

# Worker 2
scp bin/manual/setup-tailscale.sh ubuntu@130.61.47.55:/tmp/
ssh ubuntu@130.61.47.55 "sudo TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' HOSTNAME='dokploy-worker-2' bash /tmp/setup-tailscale.sh"
```

### One-liner (all instances)

```bash
export TAILSCALE_AUTH_KEY='tskey-auth-xxx...'

for host in "141.147.10.90:dokploy-main" "130.61.113.138:dokploy-worker-1" "130.61.47.55:dokploy-worker-2"; do
    IP="${host%%:*}"
    NAME="${host##*:}"
    echo "=== Setting up $NAME ($IP) ==="
    scp bin/manual/setup-tailscale.sh ubuntu@$IP:/tmp/
    ssh ubuntu@$IP "sudo TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' HOSTNAME='$NAME' bash /tmp/setup-tailscale.sh"
done
```

### Optional: Subnet Router (advertise VCN routes)

To access other VCN resources via Tailscale, set up the main instance as a subnet router:

```bash
ssh ubuntu@141.147.10.90 "sudo TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' HOSTNAME='dokploy-main' ADVERTISE_ROUTES='10.0.0.0/24,169.254.169.254/32' bash /tmp/setup-tailscale.sh"
```

Then approve the routes in Tailscale admin console.

### Verification

After setup, verify connectivity:

```bash
# Check Tailscale status on each instance
ssh ubuntu@141.147.10.90 "tailscale status"

# From your local machine (with Tailscale installed)
tailscale status

# Test direct connection (not relayed)
tailscale ping dokploy-main

# SSH via Tailscale
ssh ubuntu@dokploy-main
ssh ubuntu@dokploy-worker-1
ssh ubuntu@dokploy-worker-2

# Access Dokploy UI directly
open http://dokploy-main:3000
```

## OCI-Specific Configuration

The script handles these OCI requirements automatically:
- iptables rule for UDP 41641 (Tailscale direct connections)
- UFW rules for Tailscale interface and port
- netfilter-persistent to save iptables rules

Reference: https://tailscale.com/kb/1149/cloud-oracle
