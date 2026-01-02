#!/bin/bash
set -euo pipefail

# Security: Do NOT copy SSH keys to root - use ubuntu user with sudo instead
# Root login is disabled in sshd_config (PermitRootLogin prohibit-password only allows key auth,
# and we don't provide root with keys)

# Add ubuntu user to sudoers
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# OpenSSH
apt install -y openssh-server
systemctl status sshd

# SSH Hardening - secure sshd configuration
cat >> /etc/ssh/sshd_config.d/99-security-hardening.conf << 'EOF'
# Security hardening settings
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
X11Forwarding no
MaxAuthTries 3
MaxStartups 10:30:60
AllowAgentForwarding no
AllowTcpForwarding no
EOF

systemctl restart sshd

# Wait for network and install Docker
# Security: Download scripts first, log hash for audit, then execute
DOCKER_SCRIPT=$(mktemp)
curl --fail --retry 10 --retry-all-errors -fsSL https://get.docker.com -o "$DOCKER_SCRIPT"
echo "Docker install script SHA256: $(sha256sum "$DOCKER_SCRIPT")"
bash "$DOCKER_SCRIPT"
rm -f "$DOCKER_SCRIPT"
systemctl enable --now docker

# Install Dokploy
# Security: Download script first, log hash for audit, then execute
DOKPLOY_SCRIPT=$(mktemp)
curl --fail --retry 10 --retry-all-errors -fsSL https://dokploy.com/install.sh -o "$DOKPLOY_SCRIPT"
echo "Dokploy install script SHA256: $(sha256sum "$DOKPLOY_SCRIPT")"
bash "$DOKPLOY_SCRIPT"
rm -f "$DOKPLOY_SCRIPT"

# Docker Security Hardening - configure daemon security options
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "live-restore": true,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
EOF

# Restart Docker to apply security settings
systemctl restart docker

# UFW Firewall Configuration
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH - from VCN only (consistent with Terraform security list)
ufw allow from 10.0.0.0/16 to any port 22 proto tcp comment 'SSH from VCN'

# HTTP/HTTPS - public access
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Traefik proxy ports - public access
ufw allow 81/tcp comment 'Traefik HTTP'
ufw allow 444/tcp comment 'Traefik HTTPS'

# Docker Swarm ports - VCN only (internal cluster communication)
ufw allow from 10.0.0.0/16 to any port 2376 proto tcp comment 'Docker Swarm API (VCN)'
ufw allow from 10.0.0.0/16 to any port 2377 proto tcp comment 'Docker Swarm mgmt (VCN)'
ufw allow from 10.0.0.0/16 to any port 7946 proto tcp comment 'Docker Swarm node TCP (VCN)'
ufw allow from 10.0.0.0/16 to any port 7946 proto udp comment 'Docker Swarm node UDP (VCN)'
ufw allow from 10.0.0.0/16 to any port 4789 proto udp comment 'Docker overlay network (VCN)'

# Dokploy UI - VCN only (access via Traefik for public)
ufw allow from 10.0.0.0/16 to any port 3000 proto tcp comment 'Dokploy UI (VCN)'

# Enable UFW
ufw --force enable

# iptables rules for OCI (required alongside UFW)
# Note: Port 3000 NOT exposed publicly - access via Traefik only
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 81 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 444 -j ACCEPT
iptables -I INPUT 1 -p tcp -s 10.0.0.0/16 --dport 2377 -j ACCEPT
iptables -I INPUT 1 -p tcp -s 10.0.0.0/16 --dport 7946 -j ACCEPT
iptables -I INPUT 1 -p udp -s 10.0.0.0/16 --dport 7946 -j ACCEPT
iptables -I INPUT 1 -p udp -s 10.0.0.0/16 --dport 4789 -j ACCEPT

netfilter-persistent save

# =============================================================================
# Tailscale VPN (optional)
# =============================================================================
%{ if enable_tailscale && tailscale_auth_key != "" ~}
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Configure Tailscale with auth key
# --ssh: Enable Tailscale SSH (access without managing SSH keys)
# --accept-routes: Accept routes advertised by other nodes
# --accept-dns: Use Tailscale's MagicDNS
tailscale up --authkey="${tailscale_auth_key}" --ssh --accept-routes --accept-dns=true --hostname="dokploy-main"

# Allow Tailscale through UFW (for direct connections, optional - works via DERP without this)
ufw allow in on tailscale0 comment 'Tailscale'
ufw allow 41641/udp comment 'Tailscale direct'
%{ endif ~}