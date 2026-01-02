# OCI Bastion Service Guide

This guide explains how to use the Oracle Cloud Infrastructure (OCI) Bastion service for secure SSH access to your Dokploy instances.

## Overview

OCI Bastion provides secure, time-limited SSH access to resources without requiring public IP addresses or VPN connections. It acts as a managed jump host, eliminating the need to maintain your own bastion infrastructure.

> **Note:** The Bastion service is automatically provisioned via Terraform when `enable_bastion = true` (default). This guide focuses on **using** the Bastion to create SSH sessions.

### Session Types

| Type | Use Case | Requirements |
|------|----------|--------------|
| **Managed SSH** | Direct SSH to compute instances | Bastion plugin enabled on instance |
| **Port Forwarding** | SSH tunnel to any IP/port | Target IP and port accessible from bastion subnet |

### Benefits

- No public IPs required on target instances
- Time-limited sessions (30-180 minutes)
- Audit trail of all connections
- No infrastructure to maintain
- IP allowlist for additional security

---

## Prerequisites

Before using the Bastion, ensure you have:

1. **OCI CLI installed and configured**
   ```bash
   oci --version
   oci setup config  # if not configured
   ```

2. **SSH key pair**
   ```bash
   # Generate if needed
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_bastion
   ```

3. **Your public IP address** (for CIDR allowlist)
   ```bash
   curl -s ifconfig.me
   ```

---

## Terraform Configuration

The Bastion is managed via Terraform with these variables in `variables.tf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_bastion` | `true` | Enable/disable Bastion service |
| `bastion_allowed_cidrs` | `["0.0.0.0/0"]` | IPs allowed to connect (restrict for security) |
| `bastion_session_ttl` | `10800` | Max session duration in seconds (3 hours) |

### Restricting Access (Recommended)

Update your Terraform variables to restrict Bastion access to specific IPs:

```hcl
# In terraform.tfvars or via OCI Resource Manager
bastion_allowed_cidrs = ["YOUR_IP/32"]
```

### Get Bastion Details

After deployment, get the Bastion OCID from Terraform outputs:

```bash
# Via OCI CLI (from Resource Manager stack outputs)
oci resource-manager job get-job-logs --job-id <latest-apply-job-id> | grep bastion_id

# Or list bastions directly
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q"
oci bastion bastion list \
  --compartment-id $COMPARTMENT_ID \
  --query 'data[].{Name:name,ID:id,State:"lifecycle-state"}' \
  --output table
```

---

## Step 1: Enable Bastion Plugin on Instances

For **Managed SSH sessions**, the Bastion plugin must be enabled on target instances.

> **Note:** The Bastion plugin is configured in Terraform (`main.tf`) but set to `DISABLED` by default as it requires manual activation after deployment.

### Via OCI CLI (Recommended)

```bash
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q"

# Get main instance OCID
INSTANCE_ID=$(oci compute instance list \
  --compartment-id $COMPARTMENT_ID \
  --display-name "dokploy-main*" \
  --query 'data[0].id' --raw-output)

# Enable bastion plugin
oci compute instance update \
  --instance-id $INSTANCE_ID \
  --agent-config '{"pluginsConfig":[{"name":"Bastion","desiredState":"ENABLED"}]}'

# Enable on workers too (optional)
for WORKER_ID in $(oci compute instance list \
  --compartment-id $COMPARTMENT_ID \
  --display-name "dokploy-worker*" \
  --query 'data[].id' --raw-output); do
  oci compute instance update \
    --instance-id $WORKER_ID \
    --agent-config '{"pluginsConfig":[{"name":"Bastion","desiredState":"ENABLED"}]}'
done
```

### Via OCI Console

1. Navigate to **Compute > Instances**
2. Select your instance (e.g., `dokploy-main-cli7h`)
3. Go to **Oracle Cloud Agent** tab
4. Enable **Bastion** plugin
5. Wait for status to show "Running"

### Verify Plugin Status

```bash
oci compute instance get \
  --instance-id $INSTANCE_ID \
  --query 'data."agent-config"."plugins-config"[?name==`Bastion`]' \
  --output table
```

---

## Step 2: Create a Session

### Get Bastion OCID

```bash
BASTION_ID=$(oci bastion bastion list \
  --compartment-id $COMPARTMENT_ID \
  --name dokploy-bastion \
  --query 'data[0].id' --raw-output)

echo "Bastion ID: $BASTION_ID"
```

### Option A: Managed SSH Session

Best for direct SSH access to compute instances.

```bash
# Get target instance OCID
INSTANCE_ID=$(oci compute instance list \
  --compartment-id $COMPARTMENT_ID \
  --display-name "dokploy-main*" \
  --query 'data[0].id' --raw-output)

# Create managed SSH session
oci bastion session create-managed-ssh \
  --bastion-id $BASTION_ID \
  --target-resource-id $INSTANCE_ID \
  --target-os-username ubuntu \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --session-ttl 10800 \
  --display-name "ssh-dokploy-main" \
  --wait-for-state SUCCEEDED
```

### Option B: Port Forwarding Session

Best for tunnelling to specific ports (SSH, databases, web UIs).

```bash
# Create port forwarding session for SSH
oci bastion session create-port-forwarding \
  --bastion-id $BASTION_ID \
  --target-private-ip 10.0.0.253 \
  --target-port 22 \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --session-ttl 10800 \
  --display-name "pf-dokploy-main-ssh" \
  --wait-for-state SUCCEEDED
```

---

## Step 3: Connect via SSH

### List Active Sessions

```bash
oci bastion session list \
  --bastion-id $BASTION_ID \
  --session-lifecycle-state ACTIVE \
  --query 'data[].{Name:"display-name",State:"lifecycle-state",Created:"time-created",TTL:"session-ttl-in-seconds"}' \
  --output table
```

### Get SSH Command

```bash
# Get session OCID
SESSION_ID=$(oci bastion session list \
  --bastion-id $BASTION_ID \
  --session-lifecycle-state ACTIVE \
  --display-name "ssh-dokploy-main" \
  --query 'data[0].id' --raw-output)

# Get connection details
oci bastion session get \
  --session-id $SESSION_ID \
  --query 'data."ssh-metadata"'
```

### Connect: Managed SSH Session

The SSH command for managed sessions looks like:

```bash
ssh -i ~/.ssh/id_rsa \
  -o ProxyCommand="ssh -i ~/.ssh/id_rsa -W %h:%p -p 22 ocid1.bastionsession.oc1.eu-frankfurt-1.xxxxx@host.bastion.eu-frankfurt-1.oci.oraclecloud.com" \
  -p 22 ubuntu@10.0.0.253
```

### Connect: Port Forwarding Session

Port forwarding requires two steps:

```bash
# Terminal 1: Start the tunnel
ssh -i ~/.ssh/id_rsa -N -L 2222:10.0.0.253:22 -p 22 \
  ocid1.bastionsession.oc1.eu-frankfurt-1.xxxxx@host.bastion.eu-frankfurt-1.oci.oraclecloud.com

# Terminal 2: Connect through the tunnel
ssh -i ~/.ssh/id_rsa -p 2222 ubuntu@localhost
```

---

## Common Use Cases

### Access Dokploy UI (Port 3000)

```bash
# Create port forwarding session
oci bastion session create-port-forwarding \
  --bastion-id $BASTION_ID \
  --target-private-ip 10.0.0.253 \
  --target-port 3000 \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --session-ttl 10800 \
  --display-name "pf-dokploy-ui"

# Start tunnel (after session is ACTIVE)
ssh -i ~/.ssh/id_rsa -N -L 3000:10.0.0.253:3000 -p 22 \
  <session-ocid>@host.bastion.eu-frankfurt-1.oci.oraclecloud.com

# Access in browser: http://localhost:3000
```

### SSH to Worker Nodes

```bash
# Worker 1 (10.0.0.107)
oci bastion session create-port-forwarding \
  --bastion-id $BASTION_ID \
  --target-private-ip 10.0.0.107 \
  --target-port 22 \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --display-name "pf-worker-1"

# Worker 2 (10.0.0.44)
oci bastion session create-port-forwarding \
  --bastion-id $BASTION_ID \
  --target-private-ip 10.0.0.44 \
  --target-port 22 \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --display-name "pf-worker-2"
```

### Access Docker Swarm Manager (Port 2377)

```bash
oci bastion session create-port-forwarding \
  --bastion-id $BASTION_ID \
  --target-private-ip 10.0.0.253 \
  --target-port 2377 \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --display-name "pf-docker-swarm"
```

---

## Instance Reference

| Instance | Public IP | Private IP | Common Ports |
|----------|-----------|------------|--------------|
| dokploy-main | 141.147.10.90 | 10.0.0.253 | 22 (SSH), 3000 (Dokploy UI), 2377 (Swarm) |
| dokploy-worker-1 | 130.61.113.138 | 10.0.0.107 | 22 (SSH) |
| dokploy-worker-2 | 130.61.47.55 | 10.0.0.44 | 22 (SSH) |

---

## Session Management

### List All Sessions

```bash
oci bastion session list \
  --bastion-id $BASTION_ID \
  --all \
  --query 'data[].{Name:"display-name",State:"lifecycle-state",Type:"target-resource-details"."session-type"}' \
  --output table
```

### Delete a Session

```bash
oci bastion session delete \
  --session-id <session-ocid> \
  --force
```

### Update Bastion CIDR Allowlist

```bash
# Add additional IP addresses
oci bastion bastion update \
  --bastion-id $BASTION_ID \
  --client-cidr-block-allow-list '["203.0.113.45/32", "198.51.100.0/24"]'
```

### Delete Bastion

```bash
oci bastion bastion delete \
  --bastion-id $BASTION_ID \
  --force
```

---

## Troubleshooting

### Session Stuck in CREATING State

- Verify the Bastion plugin is enabled and running on the target instance
- Check that the VCN has proper route rules to the Oracle Services Network
- Ensure security list allows traffic from bastion subnet

### Connection Refused

- Verify your IP is in the bastion's CIDR allowlist
- Check session hasn't expired (max 180 minutes)
- Ensure you're using the correct private key

### Plugin Not Running

```bash
# SSH to instance directly (if it has public IP) and check
sudo systemctl status oracle-cloud-agent
sudo /usr/libexec/oracle-cloud-agent/plugins/bastionagent/bastionagent --version
```

### View Bastion Logs

```bash
# On the target instance
sudo journalctl -u oracle-cloud-agent -f
```

---

## Security Best Practices

1. **Restrict CIDR allowlist** - Only allow specific IP addresses, not `0.0.0.0/0`
2. **Use short session TTL** - Default 3 hours is usually sufficient
3. **Rotate SSH keys** - Use different keys for bastion sessions
4. **Monitor sessions** - Review active sessions regularly
5. **Delete unused sessions** - Clean up sessions that are no longer needed

---

## Quick Reference

```bash
# Set environment variables
export COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaa2cp3q2j6onjrvpkcnulkowvhhdyt4nt2sqitbgvsqgrizq5cst7q"
export BASTION_ID=$(oci bastion bastion list --compartment-id $COMPARTMENT_ID --name dokploy-bastion --query 'data[0].id' --raw-output)

# Create SSH session to main instance
oci bastion session create-managed-ssh \
  --bastion-id $BASTION_ID \
  --target-resource-id $(oci compute instance list --compartment-id $COMPARTMENT_ID --display-name "dokploy-main*" --query 'data[0].id' --raw-output) \
  --target-os-username ubuntu \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --session-ttl 10800 \
  --display-name "ssh-main"

# List active sessions
oci bastion session list --bastion-id $BASTION_ID --session-lifecycle-state ACTIVE --output table
```

---

## Additional Resources

- [OCI Bastion Documentation](https://docs.oracle.com/en-us/iaas/Content/Bastion/Concepts/bastionoverview.htm)
- [Managing Bastion Sessions](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/managingsessions.htm)
- [OCI CLI Bastion Commands](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/bastion.html)
