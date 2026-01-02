output "dokploy_dashboard" {
  value = "http://${oci_core_instance.dokploy_main.public_ip}:3000/ (wait 3-5 minutes to finish Dokploy installation)"
}

output "dokploy_worker_ips" {
  value = [for instance in oci_core_instance.dokploy_worker : "${instance.public_ip} (use it to add the server in Dokploy Dashboard)"]
}

# Bastion outputs
output "bastion_id" {
  description = "OCID of the OCI Bastion service"
  value       = var.enable_bastion ? oci_bastion_bastion.dokploy_bastion[0].id : null
}

output "bastion_name" {
  description = "Name of the OCI Bastion service"
  value       = var.enable_bastion ? oci_bastion_bastion.dokploy_bastion[0].name : null
}

output "dokploy_main_private_ip" {
  description = "Private IP of the main instance (use with Bastion for SSH)"
  value       = oci_core_instance.dokploy_main.private_ip
}

output "dokploy_worker_private_ips" {
  description = "Private IPs of worker instances (use with Bastion for SSH)"
  value       = [for instance in oci_core_instance.dokploy_worker : instance.private_ip]
}
