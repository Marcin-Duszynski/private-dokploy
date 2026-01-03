variable "ssh_authorized_keys" {
  description = "SSH public key for instances. For example: ssh-rsa AAEAAAA....3R ssh-key-2024-09-03"
  type        = string
}

variable "compartment_id" {
  description = "The OCID of the compartment. Find it: Profile → Tenancy: youruser → Tenancy information → OCID https://cloud.oracle.com/tenancy"
  type        = string
}

variable "source_image_id" {
  description = "Source Ubuntu 22.04 image OCID. Find the right one for your region: https://docs.oracle.com/en-us/iaas/images/image/128dbc42-65a9-4ed0-a2db-be7aa584c726/index.htm"
  type        = string
}

variable "num_worker_instances" {
  description = "Number of Dokploy worker instances to deploy (max 3 for free tier)."
  type        = number
  default     = 1
}

variable "availability_domain_main" {
  description = "Availability domain for dokploy-main instance. Find it Core Infrastructure → Compute → Instances → Availability domain (left menu). For example: WBJv:EU-FRANKFURT-1-AD-1"
  type        = string
}

variable "availability_domain_workers" {
  description = "Availability domain for dokploy-main instance. Find it Core Infrastructure → Compute → Instances → Availability domain (left menu). For example: WBJv:EU-FRANKFURT-1-AD-2"
  type        = string
}

variable "instance_shape" {
  description = "The shape of the instance. VM.Standard.A1.Flex is free tier eligible."
  type        = string
  default     = "VM.Standard.A1.Flex" # OCI Free
}

variable "memory_in_gbs" {
  description = "Memory in GBs for instance shape config. 6 GB is the maximum for free tier with 3 working nodes."
  type        = string
  default     = "6" # OCI Free
}

variable "ocpus" {
  description = "OCPUs for instance shape config. 1 OCPU is the maximum for free tier with 3 working nodes."
  type        = string
  default     = "1" # OCI Free
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB. Minimum 50 GB for Ubuntu. Free tier allows 200 GB total across all instances (e.g., 4 instances × 50 GB = 200 GB)."
  type        = number
  default     = 50 # OCI Free - minimum for Ubuntu, maximises available storage
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to access SSH. Default is VCN-only (10.0.0.0/16) for security. Set to specific IP (e.g., 'x.x.x.x/32') or '0.0.0.0/0' for public access."
  type        = string
  default     = "10.0.0.0/16" # VCN-only by default - requires bastion or VPN for SSH access
}

variable "enable_bastion" {
  description = "Enable OCI Bastion service for secure SSH access to instances. Required when SSH is restricted to VCN-only."
  type        = bool
  default     = true
}

variable "bastion_allowed_cidrs" {
  description = "List of CIDR blocks allowed to connect to the Bastion service. Default allows all IPs (authentication still required)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_session_ttl" {
  description = "Maximum session time-to-live in seconds (default: 3 hours, max: 3 hours)."
  type        = number
  default     = 10800
}

# =============================================================================
# Tailscale VPN
# =============================================================================

variable "enable_tailscale" {
  description = "Enable Tailscale VPN on instances. Requires tailscale_auth_key to be set."
  type        = bool
  default     = false
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for automatic device registration. Generate at: https://login.tailscale.com/admin/settings/keys (use reusable key for multiple instances)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_advertise_routes" {
  description = "Enable Tailscale subnet router on main instance to advertise VCN routes (10.0.0.0/24) and Oracle metadata (169.254.169.254). Allows accessing VCN resources from any Tailscale device. Requires approval in Tailscale admin console."
  type        = bool
  default     = false
}
