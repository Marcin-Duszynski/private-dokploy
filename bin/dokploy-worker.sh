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

# UFW Firewall Configuration
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH - from VCN only (consistent with Terraform security list)
ufw allow from 10.0.0.0/16 to any port 22 proto tcp comment 'SSH from VCN'

# HTTP/HTTPS - public access (for container services)
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

# Enable UFW
ufw --force enable

# iptables rules for OCI (required alongside UFW)
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 81 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 444 -j ACCEPT
iptables -I INPUT 1 -p tcp -s 10.0.0.0/16 --dport 2377 -j ACCEPT
iptables -I INPUT 1 -p tcp -s 10.0.0.0/16 --dport 7946 -j ACCEPT
iptables -I INPUT 1 -p udp -s 10.0.0.0/16 --dport 7946 -j ACCEPT
iptables -I INPUT 1 -p udp -s 10.0.0.0/16 --dport 4789 -j ACCEPT

netfilter-persistent save