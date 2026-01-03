# VCN configuration
resource "oci_core_vcn" "dokploy_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_id
  display_name   = "network-dokploy-${random_string.resource_code.result}"
  dns_label      = "vcn${random_string.resource_code.result}"
}

# Subnet configuration
resource "oci_core_subnet" "dokploy_subnet" {
  cidr_block     = "10.0.0.0/24"
  compartment_id = var.compartment_id
  display_name   = "subnet-dokploy-${random_string.resource_code.result}"
  dns_label      = "subnet${random_string.resource_code.result}"
  route_table_id = oci_core_vcn.dokploy_vcn.default_route_table_id
  vcn_id         = oci_core_vcn.dokploy_vcn.id

  # Attach the security list
  security_list_ids = [oci_core_security_list.dokploy_security_list.id]
}

# Internet Gateway configuration
resource "oci_core_internet_gateway" "dokploy_internet_gateway" {
  compartment_id = var.compartment_id
  display_name   = "Internet Gateway network-dokploy"
  enabled        = true
  vcn_id         = oci_core_vcn.dokploy_vcn.id
}

# Default Route Table
resource "oci_core_default_route_table" "dokploy_default_route_table" {
  manage_default_resource_id = oci_core_vcn.dokploy_vcn.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.dokploy_internet_gateway.id
  }
}

# Security List for Dokploy
resource "oci_core_security_list" "dokploy_security_list" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.dokploy_vcn.id
  display_name   = "Dokploy Security List"

  # Ingress Rules for Dokploy (VCN only - access via Traefik instead)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"
    tcp_options {
      min = 3000
      max = 3000
    }
    description = "Allow Dokploy traffic on port 3000 (VCN only)"
  }

  # SSH - restricted to configured CIDR (VCN-only by default)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.ssh_allowed_cidr
    tcp_options {
      min = 22
      max = 22
    }
    description = "Allow SSH traffic on port 22 (${var.ssh_allowed_cidr})"
  }

  # HTTP & HTTPS traffic
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
    description = "Allow HTTP traffic on port 80"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
    description = "Allow HTTPS traffic on port 443"
  }

  # ICMP traffic
  ingress_security_rules {
    description = "ICMP traffic for 3, 4"
    icmp_options {
      code = "4"
      type = "3"
    }
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = "false"
  }

  ingress_security_rules {
    description = "ICMP traffic for 3"
    icmp_options {
      code = "-1"
      type = "3"
    }
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless   = "false"
  }

  # Traefik Proxy
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 81
      max = 81
    }
    description = "Allow Traefik HTTP traffic on port 81"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 444
      max = 444
    }
    description = "Allow Traefik HTTPS traffic on port 444"
  }

  # Ingress rules for Docker Swarm (VCN only - internal cluster communication)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"
    tcp_options {
      min = 2376
      max = 2376
    }
    description = "Allow Docker Swarm traffic on port 2376 (VCN only)"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"
    tcp_options {
      min = 2377
      max = 2377
    }
    description = "Allow Docker Swarm management on port 2377 (VCN only)"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"
    tcp_options {
      min = 7946
      max = 7946
    }
    description = "Allow Docker Swarm node communication on port 7946 (VCN only)"
  }

  ingress_security_rules {
    protocol = "17" # UDP
    source   = "10.0.0.0/16"
    udp_options {
      min = 7946
      max = 7946
    }
    description = "Allow Docker Swarm UDP on port 7946 (VCN only)"
  }

  ingress_security_rules {
    protocol = "17" # UDP
    source   = "10.0.0.0/16"
    udp_options {
      min = 4789
      max = 4789
    }
    description = "Allow Docker Swarm overlay network on port 4789 (VCN only)"
  }

  # Tailscale direct connections (optional, stateless per Tailscale docs)
  dynamic "ingress_security_rules" {
    for_each = var.enable_tailscale ? [1] : []
    content {
      protocol  = "17" # UDP
      source    = "0.0.0.0/0"
      stateless = true # Required for Tailscale NAT detection
      udp_options {
        min = 41641
        max = 41641
      }
      description = "Tailscale direct connections (stateless)"
    }
  }

  # Egress Rule (optional, if needed)
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all egress traffic"
  }
}

# Network Security Group for finer-grained instance-level control
resource "oci_core_network_security_group" "dokploy_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.dokploy_vcn.id
  display_name   = "dokploy-nsg-${random_string.resource_code.result}"
}

# NSG Rules - SSH (restricted)
resource "oci_core_network_security_group_security_rule" "nsg_ssh" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.ssh_allowed_cidr
  source_type               = "CIDR_BLOCK"
  description               = "SSH access (${var.ssh_allowed_cidr})"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# NSG Rules - HTTP/HTTPS (public)
resource "oci_core_network_security_group_security_rule" "nsg_http" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "HTTP access"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_https" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "HTTPS access"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# NSG Rules - Traefik (public)
resource "oci_core_network_security_group_security_rule" "nsg_traefik_http" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Traefik HTTP"

  tcp_options {
    destination_port_range {
      min = 81
      max = 81
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_traefik_https" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Traefik HTTPS"

  tcp_options {
    destination_port_range {
      min = 444
      max = 444
    }
  }
}

# NSG Rules - Docker Swarm (VCN only)
resource "oci_core_network_security_group_security_rule" "nsg_swarm_mgmt" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "10.0.0.0/16"
  source_type               = "CIDR_BLOCK"
  description               = "Docker Swarm management (VCN only)"

  tcp_options {
    destination_port_range {
      min = 2377
      max = 2377
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_swarm_node_tcp" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "10.0.0.0/16"
  source_type               = "CIDR_BLOCK"
  description               = "Docker Swarm node communication TCP (VCN only)"

  tcp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_swarm_node_udp" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = "10.0.0.0/16"
  source_type               = "CIDR_BLOCK"
  description               = "Docker Swarm node communication UDP (VCN only)"

  udp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_swarm_overlay" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = "10.0.0.0/16"
  source_type               = "CIDR_BLOCK"
  description               = "Docker Swarm overlay network (VCN only)"

  udp_options {
    destination_port_range {
      min = 4789
      max = 4789
    }
  }
}

# NSG Rules - Tailscale (optional)
resource "oci_core_network_security_group_security_rule" "nsg_tailscale" {
  count                     = var.enable_tailscale ? 1 : 0
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Tailscale direct connections"

  udp_options {
    destination_port_range {
      min = 41641
      max = 41641
    }
  }
}

# NSG Rules - Egress (allow all)
resource "oci_core_network_security_group_security_rule" "nsg_egress" {
  network_security_group_id = oci_core_network_security_group.dokploy_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all egress"
}

# =============================================================================
# OCI Bastion Service
# =============================================================================
# Provides secure SSH access to instances without exposing SSH to the internet.
# Sessions are time-limited and require OCI authentication.

resource "oci_bastion_bastion" "dokploy_bastion" {
  count = var.enable_bastion ? 1 : 0

  compartment_id               = var.compartment_id
  bastion_type                 = "STANDARD"
  target_subnet_id             = oci_core_subnet.dokploy_subnet.id
  name                         = "dokploy-bastion-${random_string.resource_code.result}"
  client_cidr_block_allow_list = var.bastion_allowed_cidrs
  max_session_ttl_in_seconds   = var.bastion_session_ttl

  # Bastion does not require public IP - it's a managed service
}
