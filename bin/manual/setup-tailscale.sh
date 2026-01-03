#!/bin/bash
# =============================================================================
# Tailscale VPN Setup Script for OCI
# Based on: https://tailscale.com/kb/1149/cloud-oracle
# Run this manually on each instance via SSH
# =============================================================================
set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Configuration - SET THESE BEFORE RUNNING
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
HOSTNAME="${HOSTNAME:-$(hostname)}"
ADVERTISE_ROUTES="${ADVERTISE_ROUTES:-}"  # Optional: e.g., "10.0.0.0/24,169.254.169.254/32"

# Validate auth key
if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
    echo "Error: TAILSCALE_AUTH_KEY environment variable is required"
    echo ""
    echo "Usage:"
    echo "  sudo TAILSCALE_AUTH_KEY='tskey-auth-xxx...' HOSTNAME='dokploy-main' ./setup-tailscale.sh"
    echo ""
    echo "Optional - advertise VCN routes (for subnet router):"
    echo "  sudo TAILSCALE_AUTH_KEY='...' HOSTNAME='dokploy-main' ADVERTISE_ROUTES='10.0.0.0/24,169.254.169.254/32' ./setup-tailscale.sh"
    echo ""
    echo "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
    exit 1
fi

echo "=== Installing Tailscale ==="
curl -fsSL https://tailscale.com/install.sh | sh

echo "=== Configuring OCI iptables for Tailscale ==="
# OCI-specific: Add iptables rules for Tailscale UDP port
# Reference: https://tailscale.com/kb/1149/cloud-oracle
iptables -I INPUT 1 -p udp --dport 41641 -j ACCEPT
netfilter-persistent save

echo "=== Configuring UFW for Tailscale ==="
# Allow Tailscale interface
ufw allow in on tailscale0 comment 'Tailscale'
# Allow Tailscale direct connections (reduces latency vs DERP relay)
ufw allow 41641/udp comment 'Tailscale direct'

echo "=== Starting Tailscale ==="
echo "Auth key: ${TAILSCALE_AUTH_KEY:0:15}..."
echo "Hostname: $HOSTNAME"

# Build tailscale up command
TAILSCALE_ARGS=(
    --authkey="$TAILSCALE_AUTH_KEY"
    --ssh                    # Enable Tailscale SSH
    --accept-routes          # Accept routes from other nodes
    --accept-dns=true        # Use MagicDNS
    --hostname="$HOSTNAME"
)

# Add route advertisement if specified (for subnet router setup)
if [[ -n "$ADVERTISE_ROUTES" ]]; then
    echo "Advertising routes: $ADVERTISE_ROUTES"
    TAILSCALE_ARGS+=(--advertise-routes="$ADVERTISE_ROUTES")
fi

tailscale up "${TAILSCALE_ARGS[@]}"

echo "=== Tailscale Status ==="
tailscale status

echo ""
echo "=== Setup Complete ==="
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'pending')"
echo ""
echo "You can now access this instance via Tailscale:"
echo "  ssh ubuntu@$HOSTNAME"
echo ""
echo "To verify direct connection (not relayed):"
echo "  tailscale ping $HOSTNAME"
