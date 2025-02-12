# Provides output after deployment with the FQDN and ignition file used

output "domain_name" {
  description = "The FQDN of the provisioned node."
  value       = libvirt_domain.node.name
}

output "ignition_file" {
  description = "Path to the generated Ignition file."
  value       = "${path.module}/${var.hostname}.ign"
}

